"""게임 서버 온라인/오프라인 감시.

- probe_server: TCP(마인크래프트 SLP)와 A2S(Steam 쿼리, UDP — 팰월드·Source 계열)를
  병행해 온라인 여부 판단. 먼저 응답하는 쪽 채택.
- GameMonitor: 주기적으로 감시하고 상태 전환 시 지정 채널에 (역할 멘션과 함께) 알림.
"""

from __future__ import annotations

import asyncio
import json
import struct
import time
from pathlib import Path

import discord

from .config import GAME_MAX_WATCHES, GAME_PROBE_TIMEOUT, MC_DEFAULT_PORT, log


def parse_address(text: str) -> tuple[str, int] | None:
    """'host:port' 또는 'host'(포트 생략=25565) 를 (host, port) 로 파싱. 잘못되면 None."""
    text = (text or "").strip()
    if not text:
        return None
    # IPv6 대괄호 표기는 지원하지 않음(게임 서버는 대부분 IPv4/도메인) — ':' 다수면 거부
    if text.startswith("["):
        return None
    if text.count(":") > 1:
        return None
    if ":" in text:
        host, _, port_s = text.rpartition(":")
        host = host.strip()
        try:
            port = int(port_s)
        except ValueError:
            return None
    else:
        host, port = text, MC_DEFAULT_PORT
    if not host or len(host) > 255 or not (1 <= port <= 65535):
        return None
    return host, port


def _mc_varint(value: int) -> bytes:
    """마인크래프트 프로토콜 VarInt 인코딩 (부호는 32비트로 취급)."""
    value &= 0xFFFFFFFF
    out = bytearray()
    while True:
        b = value & 0x7F
        value >>= 7
        if value:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


async def _mc_read_varint(reader: asyncio.StreamReader) -> int:
    num = 0
    for i in range(5):
        chunk = await reader.readexactly(1)
        b = chunk[0]
        num |= (b & 0x7F) << (7 * i)
        if not (b & 0x80):
            break
    return num


async def _minecraft_status(host: str, port: int, reader, writer) -> dict | None:
    """마인크래프트 Server List Ping (status) 로 플레이어 수/버전 조회. 실패 시 None."""
    host_b = host.encode("utf-8")
    handshake = (
        b"\x00"                        # 패킷 ID 0x00 (handshake)
        + _mc_varint(-1)               # 프로토콜 버전 (-1 = 미지정)
        + _mc_varint(len(host_b)) + host_b
        + struct.pack(">H", port)
        + b"\x01"                      # next state = 1 (status)
    )
    writer.write(_mc_varint(len(handshake)) + handshake)
    writer.write(_mc_varint(1) + b"\x00")   # status request (패킷 ID 0x00, 본문 없음)
    await writer.drain()

    await _mc_read_varint(reader)               # 전체 패킷 길이 (사용 안 함)
    packet_id = await _mc_read_varint(reader)
    if packet_id != 0x00:
        return None
    json_len = await _mc_read_varint(reader)
    if json_len <= 0 or json_len > 262144:      # 방어: 비정상 길이 거부
        return None
    raw = await reader.readexactly(json_len)
    data = json.loads(raw.decode("utf-8", "replace"))
    players = data.get("players") or {}
    version = data.get("version") or {}
    return {
        "online": players.get("online"),
        "max": players.get("max"),
        "version": version.get("name"),
    }


async def _probe_tcp(host: str, port: int, timeout: float) -> tuple[bool, str]:
    """TCP 연결로 온라인 판단. 25565 포트는 마인크래프트 SLP 로 상세정보도 시도."""
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection(host, port), timeout)
    except (OSError, asyncio.TimeoutError):
        return False, "연결 실패"
    except Exception as exc:  # noqa: BLE001 - DNS 실패 등도 오프라인으로 간주
        return False, f"연결 오류: {type(exc).__name__}"

    try:
        if port == MC_DEFAULT_PORT:
            try:
                info = await asyncio.wait_for(_minecraft_status(host, port, reader, writer), timeout)
            except Exception:  # noqa: BLE001 - SLP 실패해도 TCP 가 붙었으면 온라인
                info = None
            if info and info.get("online") is not None:
                ver = f" · {info['version']}" if info.get("version") else ""
                return True, f"플레이어 {info['online']}/{info.get('max', '?')}{ver}"
        return True, "포트 열림"
    finally:
        writer.close()
        try:
            await asyncio.wait_for(writer.wait_closed(), timeout)
        except Exception:  # noqa: BLE001
            pass


# ── A2S (Steam 서버 쿼리, UDP) — 팰월드·ARK·Source 계열 ──
_A2S_INFO_QUERY = b"\xff\xff\xff\xff\x54Source Engine Query\x00"


class _A2SProtocol(asyncio.DatagramProtocol):
    def __init__(self) -> None:
        self.queue: asyncio.Queue = asyncio.Queue()

    def datagram_received(self, data, addr) -> None:
        self.queue.put_nowait(data)

    def error_received(self, exc) -> None:  # ICMP port-unreachable 등
        self.queue.put_nowait(None)


def _parse_a2s_info(data: bytes) -> dict | None:
    """A2S_INFO 응답(0x49) 에서 이름/플레이어 수 파싱."""
    def read_cstr(buf: bytes, i: int) -> tuple[str, int]:
        end = buf.index(0, i)
        return buf[i:end].decode("utf-8", "replace"), end + 1

    try:
        i = 5 + 1  # magic(4)+header(1) 다음, protocol(1) 건너뜀
        name, i = read_cstr(data, i)
        _map, i = read_cstr(data, i)
        _folder, i = read_cstr(data, i)
        _game, i = read_cstr(data, i)
        i += 2  # steam app id (short)
        return {"name": name, "players": data[i], "max": data[i + 1]}
    except (IndexError, ValueError):
        return None


async def a2s_info(host: str, port: int, timeout: float = GAME_PROBE_TIMEOUT) -> dict | None:
    """Steam A2S_INFO(UDP) 쿼리. 응답하면 {name,players,max}, 아니면 None."""
    loop = asyncio.get_running_loop()
    try:
        transport, proto = await loop.create_datagram_endpoint(
            _A2SProtocol, remote_addr=(host, port)
        )
    except Exception:  # noqa: BLE001 - DNS/소켓 실패 → 응답 없음으로 간주
        return None
    try:
        transport.sendto(_A2S_INFO_QUERY)
        data = await asyncio.wait_for(proto.queue.get(), timeout)
        if data and len(data) >= 9 and data[4] == 0x41:      # 챌린지 → 재요청
            transport.sendto(_A2S_INFO_QUERY + data[5:9])
            data = await asyncio.wait_for(proto.queue.get(), timeout)
        if not data or len(data) < 6 or data[4] != 0x49:
            return None
        return _parse_a2s_info(data)
    except (asyncio.TimeoutError, OSError):
        return None
    finally:
        transport.close()


async def probe_server(host: str, port: int, timeout: float = GAME_PROBE_TIMEOUT) -> tuple[bool, str]:
    """온라인 여부 판단. TCP(마인크래프트 SLP 포함)와 A2S(UDP, 팰월드·Source 계열)를
    병행해, 먼저 '온라인'으로 확인되는 쪽을 채택한다. 둘 다 무응답이면 오프라인.
    반환: (online 여부, 사람이 읽을 상세 문자열)."""
    async def _tcp() -> tuple[bool, str]:
        return await _probe_tcp(host, port, timeout)

    async def _udp() -> tuple[bool, str]:
        info = await a2s_info(host, port, timeout)
        if info is None:
            return False, ""
        if info.get("players") is not None:
            return True, f"플레이어 {info['players']}/{info.get('max', '?')}"
        return True, "온라인 (쿼리 응답)"

    tasks = {asyncio.ensure_future(_tcp()), asyncio.ensure_future(_udp())}
    result = (False, "연결 실패")
    try:
        pending = tasks
        while pending:
            done, pending = await asyncio.wait(pending, return_when=asyncio.FIRST_COMPLETED)
            winner = None
            for d in done:
                try:
                    ok, detail = d.result()
                except Exception:  # noqa: BLE001
                    continue
                if ok:
                    winner = (True, detail)
                    break
            if winner:
                result = winner
                break
    finally:
        for t in tasks:
            if not t.done():
                t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
    return result


class GameMonitor:
    """게임 서버 온라인/오프라인 상태를 주기적으로 감시하고 전환 시 채널에 알린다."""

    def __init__(self, path: Path, client: discord.Client, poll_sec: int, fail_threshold: int):
        self.path = path
        self.client = client
        self.poll_sec = poll_sec
        self.fail_threshold = fail_threshold
        self._watches: dict[str, dict] = {}   # key = "channel_id:host:port"
        self._task: asyncio.Task | None = None
        self._lock = asyncio.Lock()
        self._load()

    # ── 영속화 ──────────────────────────────────────────────────────────
    @staticmethod
    def _key(channel_id: int, host: str, port: int) -> str:
        return f"{channel_id}:{host.lower()}:{port}"

    def _load(self) -> None:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                self._watches = {k: v for k, v in data.items() if isinstance(v, dict)}
        except FileNotFoundError:
            self._watches = {}
        except (json.JSONDecodeError, OSError) as exc:
            log.warning("감시 목록을 읽지 못해 새로 시작합니다: %s", exc)
            self._watches = {}

    def _save(self) -> None:
        # 저장 시 전이용 필드('_' 접두)는 제외
        clean = {
            k: {kk: vv for kk, vv in v.items() if not kk.startswith("_")}
            for k, v in self._watches.items()
        }
        try:
            self.path.write_text(json.dumps(clean, ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError as exc:
            log.warning("감시 목록 저장 실패: %s", exc)

    # ── 목록 관리 (슬래시 명령에서 호출) ──────────────────────────────────
    def add(self, channel_id: int, guild_id: int | None, host: str, port: int,
            label: str, role_id: int | None = None) -> tuple[bool, str]:
        # 알림 채널(channel_id) 기준으로 중복 판정 — 같은 서버를 채널별로 감시 가능
        key = self._key(channel_id, host, port)
        if key in self._watches:
            return False, "이미 그 채널에서 감시 중인 서버예요."
        if len(self._watches) >= GAME_MAX_WATCHES:
            return False, f"감시 목록이 가득 찼어요 (상한 {GAME_MAX_WATCHES}개)."
        self._watches[key] = {
            "host": host, "port": port, "channel_id": channel_id, "guild_id": guild_id,
            "role_id": role_id, "label": label or "", "state": None,
            "last_detail": "", "last_check": 0, "added_at": int(time.time()),
        }
        self._save()
        return True, "추가"

    def remove(self, channel_id: int, host: str, port: int) -> bool:
        removed = self._watches.pop(self._key(channel_id, host, port), None)
        if removed is not None:
            self._save()
        return removed is not None

    def list_for_guild(self, guild_id: int | None) -> list[dict]:
        return [w for w in self._watches.values() if w.get("guild_id") == guild_id]

    # ── 감시 루프 ──────────────────────────────────────────────────────
    def start(self) -> None:
        if self._task is None or self._task.done():
            self._task = self.client.loop.create_task(self._loop())

    async def _loop(self) -> None:
        await self.client.wait_until_ready()
        log.info("게임 서버 감시 시작: %d개 (주기 %ds, 확정 %d회)",
                 len(self._watches), self.poll_sec, self.fail_threshold)
        while not self.client.is_closed():
            try:
                await self._poll_once()
            except Exception as exc:  # noqa: BLE001 - 루프는 어떤 경우에도 죽지 않게
                log.warning("게임 서버 감시 루프 오류: %s", exc)
            await asyncio.sleep(self.poll_sec)

    async def _poll_once(self) -> None:
        async with self._lock:
            watches = list(self._watches.values())
        if not watches:
            return
        results = await asyncio.gather(
            *(self._check(w) for w in watches), return_exceptions=True
        )
        if any(r is True for r in results):
            async with self._lock:
                self._save()

    async def _check(self, watch: dict) -> bool:
        """서버 1개 프로브 + 상태머신. 저장이 필요하면 True 반환."""
        online, detail = await probe_server(watch["host"], watch["port"])
        observed = "online" if online else "offline"
        watch["last_detail"] = detail
        watch["last_check"] = int(time.time())

        state = watch.get("state")
        if state is None:                      # 최초 관측 = 기준선 설정(알림 없음)
            watch["state"] = observed
            watch["_pending"] = None
            watch["_pending_count"] = 0
            return True

        if observed == state:                  # 변화 없음
            watch["_pending"] = None
            watch["_pending_count"] = 0
            return False

        # 상태가 다름 → 연속 관측 카운트(플래핑 방지)
        if watch.get("_pending") == observed:
            watch["_pending_count"] = watch.get("_pending_count", 0) + 1
        else:
            watch["_pending"] = observed
            watch["_pending_count"] = 1

        if watch["_pending_count"] >= self.fail_threshold:
            watch["state"] = observed
            watch["_pending"] = None
            watch["_pending_count"] = 0
            await self._announce(watch, observed, detail)
            return True
        return False

    async def _announce(self, watch: dict, state: str, detail: str) -> None:
        channel = self.client.get_channel(watch["channel_id"])
        if channel is None:
            try:
                channel = await self.client.fetch_channel(watch["channel_id"])
            except Exception as exc:  # noqa: BLE001 - 채널 삭제/권한 등
                log.warning("감시 알림 채널(%s) 접근 실패: %s", watch["channel_id"], exc)
                return
        addr = f"{watch['host']}:{watch['port']}"
        name = watch.get("label") or addr
        if state == "online":
            embed = discord.Embed(title="🟢 서버 온라인", color=0x2ECC71)
        else:
            embed = discord.Embed(title="🔴 서버 오프라인", color=0xE74C3C)
        embed.add_field(name="서버", value=name, inline=True)
        embed.add_field(name="주소", value=f"`{addr}`", inline=True)
        if state == "online" and detail and detail != "포트 열림":
            embed.add_field(name="상태", value=detail, inline=False)
        embed.add_field(name="시각", value=f"<t:{int(time.time())}:R>", inline=False)

        # 지정된 역할이 있으면 멘션(핑). 그 역할만 멘션 허용.
        role_id = watch.get("role_id")
        content = f"<@&{role_id}>" if role_id else None
        allowed = (discord.AllowedMentions(everyone=False, users=False,
                                           roles=[discord.Object(id=role_id)])
                   if role_id else discord.AllowedMentions.none())
        try:
            await channel.send(content=content, embed=embed, allowed_mentions=allowed)
        except discord.HTTPException as exc:
            log.warning("감시 알림 전송 실패(channel=%s): %s", watch["channel_id"], exc)
