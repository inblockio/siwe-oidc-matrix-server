# Synapse vendored patches — the registry

This directory is the **complete, canonical list of every modification we apply to
upstream Synapse** before running it. `dockerfiles/Dockerfile` is the single build
source for the Synapse image, and it applies exactly the patches listed here with
`patch --forward --batch --fuzz=0`, so **a patch that stops applying fails the image
build loudly** — never silently at runtime.

The rules are the same as `patches/element-web/README.md`, and for the same reason:

1. **No patch without an entry here.** Every entry states *what*, *why*, the
   *evidence* that made it necessary, its *upstream status*, and its *retirement
   condition* — the observable fact that lets us delete it. A patch nobody can
   retire is a fork forever.
2. **No behavioral patch without test coverage.** The entry names the test.
3. **Upstream-first.** Same three classifications: UPSTREAM DEFECT,
   UPSTREAM-TRACKED, POLICY. Only POLICY is permanent.
4. **Bump procedure** — run this for every `FROM matrixdotorg/synapse:vX.Y.Z`
   change, *before* merging the bump:

   ```bash
   # Fetch the two files at the new tag and dry-run every patch against them.
   TAG=v1.160.0
   d=$(mktemp -d); mkdir -p "$d/synapse/config" "$d/synapse/handlers"
   for f in config/experimental handlers/profile; do
     curl -sSf "https://raw.githubusercontent.com/element-hq/synapse/$TAG/synapse/$f.py" \
       -o "$d/synapse/$f.py"
   done
   for p in patches/synapse/*.patch; do
     (cd "$d" && patch -p1 --dry-run --forward --batch --fuzz=0 < "$OLDPWD/$p") \
       && echo "OK   $p" || echo "FAIL $p"
   done; rm -rf "$d"
   ```

   For each failing patch, consult its retirement condition **before**
   forward-porting: a patch that no longer applies often means upstream changed
   that code — check whether they merged it, and if so DROP the patch rather than
   porting it by reflex.
5. **`patch`, not `git apply`.** `matrixdotorg/synapse:v1.159.0` ships neither
   `git` nor `patch` (verified 2026-09-10), and the installed tree under
   `site-packages/` is not a git repository. The Dockerfile installs `patch` and
   resolves the `synapse` package directory at build time via
   `python -c 'import synapse'`, rather than hard-coding `python3.13` — a base
   image that bumps its Python would otherwise silently skip the patch.
6. **Do not COPY whole pre-patched files in.** That would silently pin our stale
   copy of `handlers/profile.py` across a Synapse bump, quietly reverting whatever
   upstream fixed in it — including security fixes. A `.patch` that fails the
   build is the point.

---

## 1. `msc4133-profile-field-write-policy.patch` — allow/deny-list for custom profile fields

**Classification: UPSTREAM-TRACKED** ([element-hq/synapse#19980](https://github.com/element-hq/synapse/pull/19980)).

**What it does.** Adds two config keys, `experimental_features.msc4133_key_allowlist`
and `experimental_features.msc4133_key_denylist`, and a guard in
`ProfileHandler.set_profile_field` and `ProfileHandler.delete_profile_field` that
raises `403 M_FORBIDDEN` when a **non-admin** tries to write or delete a listed
custom profile field. Admins are exempt.

**Why we need it.** siwx-oidc publishes each user's DID into their Matrix profile
under the MSC4133 custom field `io.inblock.did`, as a provider-signed assertion —
it is the one identifier a relying party can trust to name a user. On stock
Synapse 1.159.0 that field is **freely user-writable with no value validation**:
`set_profile_field`'s only check is `if not by_admin and target_user != requester.user`,
which is simply *not an error* when a user writes their own profile. So any user
could overwrite their own `io.inblock.did` with **another user's DID** and
misrepresent their cryptographic identity to every client and every federating
server that reads it. The signed assertion (see the siwx-oidc repo) makes that
tampering *detectable*; this patch makes it *impossible*.

**Evidence** (all read from the v1.159.0 source, 2026-09-10):

- `synapse/handlers/profile.py:700-704` — the only authorization on a custom-field
  write is the ownership check; there is no value validation anywhere in the path.
- `synapse/rest/client/profile.py:100-103` — the stable
  `/_matrix/client/v3/profile/{user}/{field}` route is registered
  **unconditionally**; `msc4133_enabled` gates only a redundant unstable alias. The
  field is writable out of the box.
- `synapse/config/server.py:561-563` — `require_auth_for_profile_requests` defaults
  to `False`, and custom fields federate via `handlers/profile.py:809 on_profile_query`.
  So a tampered value is world-readable and reaches remote servers.
- `synapse/api/auth/mas.py:274-275` — under MSC3861/MAS, `is_server_admin()` is
  literally `"urn:synapse:admin:*" in requester.scope`, which is exactly what
  siwx-oidc's minted admin token carries (`src/admin_token.rs`). Our write lands on
  the `by_admin` branch and is unaffected by the guard.
- `synapse/rest/synapse/mas/users.py:162,178,237,389,434` — the MAS shared-secret
  API passes `by_admin=True` unconditionally, so `provision_user` and the
  displayname writes are likewise unaffected.

**Upstream status.** #19980 (author `Barry3D`, successor to the abandoned #18562 by
`anoadragon453`, both implementing issue
[#18525](https://github.com/element-hq/synapse/issues/18525)) is **OPEN but stalled**:
`CHANGES_REQUESTED` from anoadragon453 on 2026-08-13, last activity 2026-08-14, and
now `mergeable: false` / `dirty` against `develop`. The maintainer has said he may
prefer to stabilise MSC4133 *first*. We should not expect this to land soon, and we
should not open a competing PR while the author is active.

**What we took, and what we deliberately left.** Only the
`synapse/config/experimental.py` and `synapse/handlers/profile.py` hunks, taken from
PR head `d4758f2d2`. Skipped: `synapse/rest/client/capabilities.py`, the three
upstream test files, and the changelog.

- The capability advertisement is **known-broken upstream** — anoadragon453 on
  `r3777635413`: once `allowed` is specified, MSC4133 says the whole thing becomes a
  whitelist, so advertising it would make clients 403 on every *other* custom field.
  That is a spec-level defect and it is the main thing blocking the PR. Skipping it
  insulates us from however upstream resolves it.
- **Accepted consequence:** enforcement without advertisement. A client that tries
  to edit the field gets a raw `M_FORBIDDEN` rather than a greyed-out control. For a
  server-managed field users should never touch, that is acceptable.
- Every skipped line is a line we do not forward-port.

**Take it from head `d4758f2d2` only.** An earlier revision of that branch lacked the
`not by_admin and` prefix (flagged by Copilot in `r3777481806` and fixed in
`f043c26fb`, 2026-08-14). Backporting an older revision would produce a guard that
blocks *our own* admin write.

**Applies cleanly to v1.159.0** — verified, not assumed. The PR's merge base
(`c0357de4e`) carries `handlers/profile.py` and `config/experimental.py`
**byte-identical** to tag `v1.159.0`, so all five hunks land at their exact upstream
offsets under `--fuzz=0`. It does **not** apply to 1.157.x: `handlers/profile.py` is
791 lines there versus 995 at 1.159.0, and the anchors moved substantially.

**Config we set** (`entrypoints/matrix_server.sh`, `apply_did_field_protection`):

```yaml
experimental_features:
  msc4133_key_denylist: ["io.inblock.did"]
```

Denylist, **never** allowlist. `msc4133_key_allowlist` is a hard whitelist over
*every* custom profile field on the homeserver — configuring it would forbid every
other custom field our users might ever set, which is not our call to make for them.
Note also that `[]` is not `None`: an accidentally-empty allowlist bricks all
custom-field writes. Upstream's key names are kept **verbatim** so that adopting the
merged version is a no-op for our config.

**Two limits to know about, neither fixable here:**

1. **Enforcement is prospective, not retroactive.** The guard blocks new writes; it
   does not validate or migrate a value a user set *before* the config was applied.
   Upstream has the same gap (Barry3D, `r3783167037`). We close it from the other
   side: siwx-oidc re-asserts `io.inblock.did` on **every** sign-in, so a value
   written before this shipped self-heals at the user's next login without any
   janitor process.
2. **It does not cover `displayname` or `avatar_url`**, which route through
   `set_field` → `set_displayname`/`set_avatar_url` and reach the store directly,
   never touching the guarded methods. Putting `"displayname"` in the denylist would
   have zero effect. This is *desirable* here: `displayname` is the user's alias and
   must stay user-owned. The three-tier identity model (alias / MXID / DID) is
   therefore enforced structurally, not by convention.

**Test coverage.** `siwx-oidc/tests/e2e_did_field_live.rs` (`--ignored`, run against
the local e2e harness): a user token's PUT and DELETE of `io.inblock.did` each answer
403 `M_FORBIDDEN`, while siwx-oidc's minted admin token still writes it successfully,
and an unprotected control field remains user-writable.

**Retirement condition.** #19980 (or a successor implementing issue #18525) merges
and ships in a Synapse release we have adopted, with the guard still exempting
`by_admin`. Then delete this patch; the `homeserver.yaml` denylist entry stays. If
upstream lands *different* config key names, the entrypoint's `yq` lines change with
the same commit that drops the patch.
