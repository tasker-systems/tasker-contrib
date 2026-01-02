# tasker-contrib-bun

Bun integration for Tasker Core.

## Features

- **Bun.serve Integration** - Simple HTTP server with Tasker lifecycle
- **Type Definitions** - Full TypeScript types for Tasker APIs
- **Testing Utilities** - Bun test helpers

## Installation

```bash
bun add tasker-contrib-bun tasker-core-ts
```

## Quick Start

```typescript
import { TaskerServer } from 'tasker-contrib-bun';

const server = new TaskerServer({
  port: 3000,
  handlers: './handlers',
});

server.start();
```

## Status

📋 Planned
