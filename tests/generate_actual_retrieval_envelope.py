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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mcp-root", required=True)
    parser.add_argument("--brain-root", required=True)
    parser.add_argument("--query", required=True)
    return parser.parse_args()


async def run(args: argparse.Namespace) -> dict:
    mcp_root = Path(args.mcp_root).resolve()
    brain_root = Path(args.brain_root).resolve()
    environment = dict(os.environ)
    environment.update(
        {
            "PYTHONUTF8": "1",
            "YOHAN_BRAIN_ROOT": str(brain_root),
            "MEMORY_DIR": str(brain_root / "memory"),
        }
    )
    parameters = StdioServerParameters(
        command=sys.executable,
        args=["server.py"],
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
                    "query": args.query,
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
    envelope = asyncio.run(run(parse_args()))
    print(json.dumps(envelope, ensure_ascii=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
