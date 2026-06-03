#
# Pre-execution hook that gates Azure CLI write operations.
# Safe, read-only commands pass through. Known safe mitigations
# (e.g. starting a stopped PostgreSQL server) are allowed autonomously.
# All other write/mutation commands are blocked unless the run has been
# granted the RunAzCliWriteCommands permission via an approval workflow.
#
# See: https://sre.azure.com/docs/extensibility/hooks.md

from sre_agent.hooks import HookBlockedError

# ── az subcommands that modify state ──────────────────────────────────────────
WRITE_SUBCOMMANDS = {
    "create", "update", "delete", "set", "assign", "remove",
    "start", "stop", "restart", "scale", "deploy", "apply",
    "patch", "rotate", "reset", "enable", "disable",
}

# ── Commands that are safe to run autonomously (no approval needed) ───────────
# Each entry is a tuple of tokens that must ALL appear in the command.
# Order does not matter; matching is case-insensitive.
AUTONOMOUS_ALLOW_LIST = [
    # Starting a stopped PostgreSQL server is a safe, non-destructive mitigation
    ("postgres", "flexible-server", "start"),
]

# ── Commands that must ALWAYS require explicit user approval ──────────────────
# Even if RunAzCliWriteCommands permission is present, these are blocked
# unless the approval was specifically for this class of operation.
HIGH_RISK_PATTERNS = [
    # Password resets change credentials — must always have human in the loop
    ("postgres", "flexible-server", "update"),
    # Secret changes can break running containers
    ("containerapp", "secret", "set"),
    # Revision triggers cause container restarts
    ("containerapp", "update"),
]


def _tokenize(command: str) -> list[str]:
    """Lowercase and split the command into tokens."""
    return command.strip().lower().split()


def _is_write_command(tokens: list[str]) -> bool:
    """Return True if the az command contains a write subcommand."""
    return any(token in WRITE_SUBCOMMANDS for token in tokens)


def _matches_pattern(tokens: list[str], pattern: tuple[str, ...]) -> bool:
    """Return True if every token in the pattern appears in the command."""
    return all(p in tokens for p in pattern)


def _is_autonomous_allowed(tokens: list[str]) -> bool:
    """Return True if the command matches a known safe mitigation."""
    return any(_matches_pattern(tokens, pat) for pat in AUTONOMOUS_ALLOW_LIST)


def _is_high_risk(tokens: list[str]) -> bool:
    """Return True if the command matches a high-risk pattern."""
    return any(_matches_pattern(tokens, pat) for pat in HIGH_RISK_PATTERNS)


def pre_execution(tool_name: str, tool_args: dict, context: dict) -> None:
    """
    Gate az CLI write operations.

    Decision tree:
    1. Non-az-CLI tools → allow (early return)
    2. Read-only az commands → allow
    3. Known safe mitigations (AUTONOMOUS_ALLOW_LIST) → allow
    4. High-risk commands (HIGH_RISK_PATTERNS) → always block
    5. Other write commands → block unless RunAzCliWriteCommands permission present
    """
    # Only gate az CLI tools
    if tool_name not in ("RunAzCliCommand", "RunAzCliWriteCommands"):
        return

    command = tool_args.get("command", "")
    tokens = _tokenize(command)

    # Read-only commands pass through
    if not _is_write_command(tokens):
        return

    # Known safe mitigations are allowed without approval
    if _is_autonomous_allowed(tokens):
        return

    # High-risk commands are ALWAYS blocked — require explicit user approval
    if _is_high_risk(tokens):
        raise HookBlockedError(
            f"BLOCKED: '{command}' is a high-risk write operation that always "
            f"requires explicit user approval. Present the command to the user "
            f"and wait for confirmation before proceeding."
        )

    # All other write commands require the RunAzCliWriteCommands permission
    permissions = context.get("permissions", [])
    if "RunAzCliWriteCommands" not in permissions:
        raise HookBlockedError(
            f"BLOCKED: '{command}' is a write operation that requires the "
            f"RunAzCliWriteCommands permission. Request approval to proceed."
        )
