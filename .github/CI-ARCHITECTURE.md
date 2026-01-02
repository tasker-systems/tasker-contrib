# CI Architecture

## Overview

Tasker Contrib's CI strategy differs fundamentally from Tasker Core:

| Aspect | Tasker Core | Tasker Contrib |
|--------|-------------|----------------|
| **Trigger scope** | Holistic (everything runs) | Path-based (selective) |
| **Coherence** | Critical (monorepo crates) | Independent (separate packages) |
| **Dependency** | Self-contained | Depends on tasker-core |
| **Build modes** | Single (pinned) | Dual (pinned + bleeding-edge) |

## Workflows

### 1. CI (ci.yml)

**Purpose**: Standard PR and merge CI with path-based triggering.

**Triggers**:
- Push to main
- Pull requests to main

**Path-based Jobs**:
| Path | Job | Why |
|------|-----|-----|
| `rails/**` | Rails tests | Ruby changes |
| `python/**` | Python tests | Python changes |
| `typescript/**` | TypeScript tests | TypeScript changes |
| `rust/**` | Rust tests | Rust changes |
| `ops/**` | Ops validation | Infrastructure changes |
| `docs/**` | Doc linting | Documentation changes |

**Dependency Mode**: Uses pinned versions from package manifests.

### 2. Bleeding Edge (bleeding-edge.yml)

**Purpose**: Test against latest tasker-core main to catch compatibility issues early.

**Triggers**:
- Repository dispatch from tasker-core (when main merges)
- Manual dispatch
- Nightly schedule (4 AM UTC)

**Artifact Strategy**:

GitHub Actions doesn't allow downloading artifacts from other repositories directly. We use:

**Option A (Current): Rebuild from source with warm cache**
- Checkout tasker-core at the triggering SHA
- Build with shared cargo cache (benefits from tasker-core's CI warming)
- ~10-15 min rebuild time on cache hit
- Artifacts uploaded: `tasker-core-binaries`, `tasker-core-ruby`, `tasker-core-python`, `tasker-core-typescript`

**Option B (Future): Download from GitHub Releases**
- tasker-core publishes artifacts on merge to main
- tasker-contrib downloads pre-built artifacts
- ~2-3 min download time
- Requires tasker-core to publish release artifacts (TBD)

**Artifacts Built** (matching tasker-core's build-workers.yml):
```
tasker-core-binaries/
├── tasker-server
├── tasker-worker
└── tasker-cli

tasker-core-ruby/
├── lib/tasker_core/tasker_worker_rb.bundle
├── lib/tasker_core/tasker_worker_rb.so
└── ...

tasker-core-python/
└── wheels/*.whl

tasker-core-typescript/
├── libtasker_worker.so
├── dist/
└── package.json
```

### 3. Upstream Check (upstream-check.yml)

**Purpose**: Monitor for new tasker-core releases, faster than dependabot.

**Triggers**:
- Daily schedule (6 AM UTC)
- Manual dispatch

**Checks**:
- crates.io for Rust crates (pgmq-notify, tasker-worker, tasker-orchestration, tasker-cli)
- PyPI for Python packages (tasker-core-py)
- RubyGems for Ruby gems (tasker-core-rb)
- npm for TypeScript packages (tasker-core-ts)

**Actions**:
- Creates GitHub issue when updates available
- Tracks version lag for deprecation warnings
- Suggests update priority (patch/minor/major)

## tasker-core CI Integration

### Existing Artifacts from tasker-core

tasker-core's `build-workers.yml` already builds and uploads:

| Artifact Name | Contents | Retention |
|---------------|----------|-----------|
| `build-artifacts` | tasker-server, tasker-worker, tasker-cli | 1 day |
| `worker-artifacts` | Ruby .bundle/.so, TypeScript dist/, Rust worker | 1 day |

### Cross-Repo Triggering

When tasker-core main merges successfully:

```yaml
# Add to tasker-core/.github/workflows/ci-success.yml
- name: Trigger tasker-contrib bleeding edge
  if: github.ref == 'refs/heads/main'
  uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.CONTRIB_TRIGGER_TOKEN }}
    repository: tasker-systems/tasker-contrib
    event-type: tasker-core-updated
    client-payload: '{"ref": "${{ github.sha }}", "run_id": "${{ github.run_id }}"}'
```

### Required Secrets

| Secret | Purpose | Repository |
|--------|---------|------------|
| `CONTRIB_TRIGGER_TOKEN` | PAT to dispatch to tasker-contrib | tasker-core |

## Version Tracking

### upstream-versions.json

Tracks pinned versions for each language:

```json
{
  "rust": {
    "tasker-worker": "0.5.0",
    "tasker-orchestration": "0.5.0",
    "tasker-cli": "0.5.0",
    "pgmq-notify": "0.5.0"
  },
  "ruby": {
    "tasker-core-rb": "0.5.0"
  },
  "python": {
    "tasker-core-py": "0.5.0"
  },
  "typescript": {
    "tasker-core-ts": "0.5.0"
  }
}
```

### Version Constraints

Each contrib package declares its own constraints:

**Ruby (gemspec)**:
```ruby
spec.add_dependency 'tasker-core-rb', '~> 0.5.0'
```

**Python (pyproject.toml)**:
```toml
dependencies = ["tasker-core-py>=0.5.0,<0.6.0"]
```

**TypeScript (package.json)**:
```json
"peerDependencies": {
  "tasker-core-ts": ">=0.5.0 <0.6.0"
}
```

## Semver Strategy for tasker-core

### Publishable Crates

| Crate | Independence | Publishing Target |
|-------|--------------|-------------------|
| `pgmq-notify` | High | crates.io (standalone) |
| `tasker-shared` | Foundation | crates.io (internal dep) |
| `tasker-orchestration` | Medium | crates.io |
| `tasker-worker` | Medium | crates.io |
| `tasker-cli` | Medium | crates.io + binary releases |

### Language Bindings (NOT separate crates)

The `tasker-worker-*` crates are **not** published to crates.io. Instead:

1. **Binary + FFI Extension**: CI builds platform-specific binaries
2. **Packaged Together**: 
   - Ruby gem includes `.bundle`/`.so`
   - Python wheel includes FFI library
   - TypeScript npm package includes FFI library
3. **Version Alignment**: Language package version matches tasker-worker semver

### Version Cascade

When `tasker-shared` changes:
1. All dependent crates need recompilation
2. Semver bump follows tasker-shared change type
3. Language bindings republish with new version

## Deprecation Mechanics

### Version Lag Warnings

| Lag | Severity | Action |
|-----|----------|--------|
| 0-1 patch | Info | No action |
| 2+ patches | Notice | Consider updating |
| 1 minor | Warning | Update within 2 weeks |
| 2+ minor | Error | Urgent update needed |
| 1+ major | Critical | Migration required |

### Deprecation Notices

When a tasker-core version is deprecated:
1. Upstream check flags it
2. Issue created with migration guide link
3. CI adds warning annotation
4. README badge shows status

## Local Development

For local development in bleeding-edge mode:

```bash
# Clone both repos
git clone git@github.com:tasker-systems/tasker-core.git
git clone git@github.com:tasker-systems/tasker-contrib.git

# Build tasker-core (matches CI build-workers.yml)
cd tasker-core
cargo build --release
cd workers/ruby && bundle exec rake compile
cd ../python && uv sync && uv run maturin develop
cd ../typescript && bun install

# Configure contrib to use local build (Gemfile uses path: dependency)
cd ../../tasker-contrib/rails/tasker-contrib-rails
bundle install
bundle exec rspec
```

See [DEVELOPMENT.md](../../DEVELOPMENT.md) for full setup instructions.

## Future Optimizations

### GitHub Releases for Artifacts

To reduce bleeding-edge build time from ~15min to ~3min:

1. **tasker-core publishes on main merge**:
   ```yaml
   # tasker-core CI adds release job
   - name: Create nightly release
     uses: softprops/action-gh-release@v1
     with:
       tag_name: nightly
       files: |
         target/release/tasker-*
         workers/ruby/lib/tasker_core/*.so
         workers/python/target/wheels/*.whl
   ```

2. **tasker-contrib downloads instead of building**:
   ```yaml
   - name: Download from release
     run: |
       gh release download nightly \
         --repo tasker-systems/tasker-core \
         --pattern "*.so" --pattern "*.whl"
   ```

### GHCR for Docker Images

If we need Docker-based testing:
- tasker-core pushes images to `ghcr.io/tasker-systems/tasker-*`
- tasker-contrib pulls pre-built images
- No build time, just pull time

## Performance Targets

| Workflow | Cold Cache | Warm Cache | Target |
|----------|------------|------------|--------|
| CI (path-based) | 10 min | 5 min | < 10 min |
| Bleeding Edge Build | 20 min | 12 min | < 15 min |
| Bleeding Edge Tests | 10 min | 8 min | < 10 min |
| Upstream Check | 2 min | 2 min | < 3 min |

## Related Documentation

- [tasker-core CI README](https://github.com/tasker-systems/tasker-core/blob/main/.github/workflows/README.md)
- [DEVELOPMENT.md](../../DEVELOPMENT.md) - Local development setup
- [TAS-126](../../docs/ticket-specs/TAS-126/) - Foundations ticket
