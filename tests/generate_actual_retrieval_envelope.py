from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mcp-root", required=True)
    parser.add_argument("--brain-root", required=True)
    parser.add_argument("--query", required=True)
    return parser.parse_args()


async def run(args: argparse.Namespace) -> dict:
    mcp_root = Path(args.mcp_root).resolve()
    brain_root = Path(args.brain_root).resolve()
    sys.path.insert(0, str(mcp_root))

    from adapters.memory_adapter import MemoryAdapter
    from core.router import SmartRouter
    from core.schema_validator import SchemaValidator
    from core.tools import ToolContext, tool_get_context

    memory = MemoryAdapter(base_dir=brain_root / "memory")
    adapters = {"memory": memory}
    context = ToolContext(adapters, SmartRouter(adapters), SchemaValidator(), entity_catalog={})
    return await tool_get_context(
        context,
        args.query,
        {
            "top_k": 5,
            "backends": ["memory"],
            "context_supplemental": False,
            "skip_roster": True,
        },
    )


def main() -> None:
    envelope = asyncio.run(run(parse_args()))
    print(json.dumps(envelope, ensure_ascii=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
