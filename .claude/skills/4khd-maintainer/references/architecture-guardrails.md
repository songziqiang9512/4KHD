# 4KHD Architecture Guardrails

## Boundaries

- `App`: app lifecycle, assembly, preferences, inspector/window controllers.
- `Shell`: workspace shell, route, sidebar, toolbar, split layout, immersive mode.
- `Shared`: cross-module AppKit views, platform bridges, services, state helpers.
- `Modules`: business-specific domain/state/services/UI.

## Module Rules

- A module may depend on `Shared` and injected services.
- A module must not import or directly call another business module.
- App assembly may compose stores and bridges, but should not absorb module behavior.
- Shell should know module IDs and exposed actions, not parser/cache details.

## Shared Rules

Move code to `Shared` only when:

- At least two modules use it now.
- The abstraction removes meaningful current duplication.
- The API name has no site-specific or business-specific meaning.

Keep code inside a module when:

- It exists for one site, one parser, one cache format, or one UI variant.
- Moving it would force generic names around business behavior.
- The second use is speculative.

## UI Rules

- Use AppKit system controls and materials first.
- Keep cards, overlays, toolbars, split views, menus, alerts, and source lists close to native macOS behavior.
- Do not reintroduce SwiftUI or SwiftUI bridge types in production code.
- Prefer behavior parity between modules before trying to unify underlying controls.
