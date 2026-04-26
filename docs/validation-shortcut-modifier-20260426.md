# Validation Log: Shortcut Modifier (`Command` vs `Control`)

Date: 2026-04-26 (Asia/Seoul)  
Repo: `/Users/huey/Projects/notion-tabs`

## Goal

- Verify whether tab-switch shortcut should be `Command+number` or `Control+number`.
- Verify against AX truth (`notion-tabs-v2 source focused-window`).

## Baseline

- `swift run notion-tabs list`
  - Focused window/tab title: `로그, 지표, 통계`
  - Focused persisted window: `[2]` with 13 tabs

## Independent Event Tests (No product code path)

Test method:
1. Post keyboard event directly via `swift -e` + `CGEvent` (`maskCommand` or `maskControl`).
2. Read result with `swift run notion-tabs-v2 source focused-window`.

Results:

1. `cmd+1` (keyCode 18)  
   - Post output: `posted cmd+1`
   - AX result: `Privy 다중 계정 연동 기획`
   - `logDir`: `logs/v2/20260426-192229-source-focused-window-fac00b37`

2. `cmd+3` (keyCode 20)  
   - Post output: `posted cmd+3`
   - AX result: `Alpha 포인트 리더보드`
   - `logDir`: `logs/v2/20260426-192238-source-focused-window-5763d400`

3. `cmd+8` (keyCode 28)  
   - Post output: `posted cmd+8`
   - AX result: `@April 1, 2026 Versus 디자인 미팅`
   - `logDir`: `logs/v2/20260426-192249-source-focused-window-9776994c`

4. `cmd+9` (keyCode 25)  
   - Post output: `posted cmd+9`
   - AX result: `법률검토 기반 사업구조 정리`
   - `logDir`: `logs/v2/20260426-192259-source-focused-window-ac3cc941`
   - Observation: current Notion behavior appears to treat `cmd+9` as “last tab” in this window.

5. `ctrl+1` (keyCode 18)  
   - Post output: `posted ctrl+1`
   - AX result: unchanged (`법률검토 기반 사업구조 정리`)
   - `logDir`: `logs/v2/20260426-192321-source-focused-window-45c9b013`

## POC1 Code Check

- `Sources/NotionTabsPOC/main.swift` `ActivationStrategy` only has:
  - `menu-only`
  - `app-first`
- No keyboard shortcut posting logic (`CGEvent` keyboard + command/control flags) found in POC1.

## Conclusion

- Shortcut modifier for this environment is **`Command`**, not `Control`.
- Current product-core `ControlNumberShortcutFocuser` modifier assumption is incorrect for this verified case.
- The right-click/context-menu symptom is consistent with wrong-modifier path + click fallback interaction.
