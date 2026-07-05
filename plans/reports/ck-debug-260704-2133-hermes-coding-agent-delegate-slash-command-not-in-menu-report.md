# Debug: `/coding-agent-delegate` (`/delegate_code`) missing from Telegram slash-command list

## Executive Summary

Two distinct, now-fully-diagnosed root causes, stacked:

1. **(Fixed, prior turn)** `skills/dev/coding-agent-delegate/SKILL.md` documented a fictional command `/delegate_code` in its `when_to_use` and examples. Hermes derives the real slash-command name from the skill's frontmatter `name:` field (`agent/skill_commands.py:400,513` in the `hermes-agent` source, `/home/ubuntu/workspace/hermes-agent`) — never from prose. The real command was always `/coding-agent-delegate`. Docs corrected to match; `/opt/hermes-optimization-guide` synced.
2. **(New, this turn)** Even the correct `/coding-agent-delegate` never appears in Telegram's native "/" autocomplete menu, because Telegram's `setMyCommands` payload is capped (`platforms.telegram.extra.command_menu.max_commands`, default **60**, Telegram hard limit **100**). Built-in commands (52) + skill-derived commands are combined and trimmed **alphabetically**; only 8 skill slots remain at the default cap of 60 (`airtable` … `audit_mcp`) before the list is cut. `coding-agent-delegate` sorts after all of those and never gets a menu slot.

**Dispatch still works.** Manually typing `/coding-agent-delegate <task>` (or the Telegram-mandatory-underscore form `/coding_agent_delegate`) and sending it *does* dispatch correctly — verified live (see Evidence). The menu is cosmetic; the internal command registry (`agent.skill_commands.get_skill_commands()`) is uncapped and unaffected by the Telegram menu cap.

## Evidence (live, ground-truth execution against the running host)

Ran directly in hermes' actual venv with the exact systemd env (`HOME=/home/hermes`, `HERMES_CONFIG=/home/hermes/.hermes/config.yaml`, `XDG_STATE_HOME=/home/hermes/.hermes/xdg_state`) — not guessed, not from docs.

- `agent.skill_commands.scan_skill_commands()` → 82 total commands, includes `'/coding-agent-delegate' -> {name: 'coding-agent-delegate', skill_md_path: '/home/hermes/.hermes/skills/coding-agent-delegate/SKILL.md', ...}`. Confirms internal registry has it correctly, regardless of menu.
- `agent.skill_commands.resolve_skill_command_key('coding-agent-delegate')` → `/coding-agent-delegate`; `resolve_skill_command_key('coding_agent_delegate')` → `/coding-agent-delegate` (underscore/hyphen interchangeable). `resolve_skill_command_key('delegate_code')` → `None` (confirms original bug — never existed under any spelling).
- `hermes_cli.commands.telegram_menu_commands(max_commands=60)` (the actual configured default; `/home/hermes/.hermes/config.yaml` has no `command_menu` override) → 60 kept, 74 hidden, `coding_agent_delegate` **NOT** in the returned list. Menu ends at `audit_mcp` after 52 built-ins consume most of the 60 slots.
- Same call with `max_commands=100` (Telegram's hard API ceiling) → `coding_agent_delegate` **IS** included, 34 still hidden (alphabetically later skills: `openhue` onward).
- Log from the original incident (`journalctl -u hermes.service`, 2026-07-04 21:17:03): `Unrecognized slash command /delegate_code from telegram — replying with unknown-command notice` (`gateway/run.py:9084`) — expected behavior given cause 1; not a gateway bug.

## Root Cause Detail

- Command-name derivation: `scan_skill_commands()` (`agent/skill_commands.py:348-415`) builds `/command` keys purely from each `SKILL.md`'s frontmatter `name:` field, hyphenated. No alias/override field exists (`grep -rn alias agent/skill_commands.py agent/skill_utils.py tools/skills_tool.py` → no hits besides an unrelated docstring).
- Menu cap + fill order: `hermes_cli/commands.py::telegram_menu_commands()` (line 889) reserves slots for `_prioritize_telegram_menu_commands(core_commands)` first (built-ins, reorderable via `platforms.telegram.extra.command_menu.priority` config — **but this priority list only reorders built-in `CommandDef` commands, not skills**), then fills whatever's left via `_collect_gateway_skill_entries()` (line 764), which always does `for cmd_key in sorted(skill_cmds)` — pure alphabetical, no way to prioritize an individual skill into the visible menu short of raising `max_commands` or renaming the skill to sort earlier.

## Fix Options (not yet applied — production host config)

`/home/hermes/.hermes/config.yaml` currently has no `platforms.telegram.extra.command_menu` block (using all defaults). To surface `/coding-agent-delegate` in the Telegram "/" menu:

```yaml
platforms:
  telegram:
    extra:
      command_menu:
        max_commands: 100   # Telegram's hard ceiling (was: default 60)
```

Verified via live re-run: raises kept-skill slots from 8 to 48, which includes `coding-agent-delegate`. Does not guarantee *every* skill (82 skill commands + 52 built-ins = 134 candidates, still 34 over the 100 hard cap) — alphabetically-late skills (`openhue` onward) remain hidden from the menu, though still dispatchable by typing them out.

No code change requires modification — this is a config value on the live host, not a repo file.

## Unresolved Questions

1. Does the user want the `max_commands: 100` config change applied now (requires editing `/home/hermes/.hermes/config.yaml` + no service restart needed — config re-read is presumably on next `setMyCommands` sync; unverified whether that's per-message or on a timer/startup only).
2. Is menu *visibility* actually required, or is "user types the full command manually" acceptable? The reported symptom (unknown-command error) is already resolved by the prior turn's doc fix — this remaining item is UX polish, not a functional block.
