# Admin Backend Structure Guide

This directory contains the backend code for admin-only capabilities under `/v1/admin/*`.

## Directory Layout

- `registerAdminRoutes.js`
  - Admin routing entrypoint (composition root).
  - Registers global admin middleware (origin allowlist check).
  - Mounts route modules.
- `routes/speciesRoutes.js`
  - Species CRUD and species-adjacent operations.
  - Includes:
    - `GET /v1/admin/species`
    - `POST /v1/admin/species`
    - `GET /v1/admin/species/:id`
    - `PATCH /v1/admin/species/:id`
    - `POST /v1/admin/species/:id/image`
    - `POST /v1/admin/species/:id/aliases`
    - `POST /v1/admin/species/:id/aliases/replace`
    - `PATCH /v1/admin/species/:id/aliases/:aliasId`
    - `DELETE /v1/admin/species/:id/aliases/:aliasId`
- `routes/mergeRoutes.js`
  - Species merge workflow.
  - Includes:
    - `POST /v1/admin/species/merge/preview`
    - `POST /v1/admin/species/merge`
- `routes/snapshotRoutes.js`
  - Snapshot and audit capabilities.
  - Includes:
    - `POST /v1/admin/species/snapshots`
    - `GET /v1/admin/species/snapshots`
    - `POST /v1/admin/species/snapshots/:id/restore`
    - `GET /v1/admin/species/audit-logs`

## Placement Rules For New Endpoints

When adding a new admin endpoint, place it by business intent rather than URL shape.

- Put in `routes/speciesRoutes.js` if endpoint is mainly about:
  - species fields (name, taxonomy, rarity, media)
  - aliases/synonyms maintenance
  - single-species editing workflow
- Put in `routes/mergeRoutes.js` if endpoint is mainly about:
  - merge validation/preview
  - merge execution/side effects
  - merge-specific rollback metadata
- Put in `routes/snapshotRoutes.js` if endpoint is mainly about:
  - snapshot create/list/restore
  - audit history, operation logs, timeline queries
- Keep `registerAdminRoutes.js` minimal:
  - middleware wiring
  - module registration only
  - no route business logic

## Decision Table (Quick)

- "Edit species fields or aliases?" -> `speciesRoutes.js`
- "Merge A/B logic?" -> `mergeRoutes.js`
- "Snapshot/audit and restore?" -> `snapshotRoutes.js`
- "Need a new shared admin-wide middleware?" -> `registerAdminRoutes.js`

## Coding Conventions For Admin Routes

- Always guard with `requireAdmin(req, res)` inside handlers.
- Return errors through `jsonError(...)` for consistent response format.
- Log important mutations with `logSpeciesAdminAction(...)`.
- Keep route modules stateless:
  - inject dependencies via function params
  - avoid hidden globals in module scope
- Keep API path prefix unchanged as `/v1/admin/*`.

## How To Add A New Admin Endpoint

1. Choose module by placement rules above.
2. Add route handler in that module (`routes/*.js`).
3. Reuse injected dependencies; do not instantiate new clients there.
4. Add audit log call if endpoint mutates data.
5. Run checks:
   - `node --check backend/server.js`
   - `node --check backend/admin/registerAdminRoutes.js`
   - `node --check backend/admin/routes/<touched-file>.js`
6. If endpoint contract changed, update:
   - frontend API constants
   - backend docs
   - any SQL/RPC migration notes

## Notes

- Keep files focused. If one route module grows too large, split by subdomain (for example: `speciesAliasesRoutes.js`, `speciesImageRoutes.js`) and register from `registerAdminRoutes.js`.
- Prefer backward-compatible API evolution to avoid breaking existing admin frontend flows.
