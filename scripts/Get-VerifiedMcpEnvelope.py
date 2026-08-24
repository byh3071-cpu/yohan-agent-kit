from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from datetime import timedelta
from pathlib import Path

from mcp import ClientSession
from mcp.client.stdio import StdioServerParameters, stdio_client


SAFE_CHILD_ENVIRONMENT = (
    "APPDATA",
    "COMSPEC",
    "LOCALAPPDATA",
    "PATH",
    "PATHEXT",
    "PROGRAMDATA",
    "SYSTEMROOT",
    "TEMP",
    "TMP",
    "USERPROFILE",
    "WINDIR",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mcp-root", required=True)
    parser.add_argument("--brain-root", required=True)
    return parser.parse_args()


def read_query() -> str:
    query = sys.stdin.buffer.read().decode("utf-8-sig")
    if not query or "\0" in query:
        raise ValueError("query stdin is empty or invalid")
    return query


async def retrieve(args: argparse.Namespace, query: str) -> dict:
    mcp_root = Path(args.mcp_root).resolve(strict=True)
    brain_root = Path(args.brain_root).resolve(strict=True)
    environment = {
        name: os.environ[name]
        for name in SAFE_CHILD_ENVIRONMENT
        if name in os.environ
    }
    environment.update(
        {
            # The prefix has a regular file as an ancestor, so no pre-existing
            # ignored bytecode can exist there. DONTWRITE keeps the run read-only.
            "PYTHONPYCACHEPREFIX": str(
                mcp_root / "server.py" / ".yohan-retrieval-no-pyc"
            ),
            "PYTHON_DOTENV_DISABLED": "1",
            "PYTHONUTF8": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
            "YOHAN_BRAIN_ROOT": str(brain_root),
            "MEMORY_DIR": str(brain_root / "memory"),
        }
    )
    parameters = StdioServerParameters(
        command=sys.executable,
        args=["-B", "server.py"],
        env=environment,
        cwd=mcp_root,
        encoding="utf-8",
    )
    async with stdio_client(parameters) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            result = await session.call_tool(
                "get_context",
                {
                    "query": query,
                    "opts": {
                        "top_k": 5,
                        "backends": ["memory"],
                        "context_supplemental": False,
                        "skip_roster": True,
                    },
                },
                read_timeout_seconds=timedelta(seconds=60),
            )
            return result.model_dump(mode="json", exclude_none=True)


def main() -> None:
    args = parse_args()
    envelope = asyncio.run(retrieve(args, read_query()))
    print(json.dumps(envelope, ensure_ascii=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
