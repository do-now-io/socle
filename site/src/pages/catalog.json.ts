// The catalog as data, for tooling: served at /socle/catalog.json (and under
// /dev/ for main), from the same read of the repository as the catalog page
// and its dependency graph (src/catalog.mjs).
import type { APIRoute } from 'astro';
import { clouds, modules } from '../catalog.mjs';

export const GET: APIRoute = () =>
  new Response(
    `${JSON.stringify(
      {
        clouds,
        modules: modules.map((m) => ({
          name: m.name,
          page: m.page,
          description: m.description,
          category: m.category,
          enabled: m.enabled,
          clouds: m.clouds ?? clouds,
          chart: m.chart,
          requires: m.requires.map((r) => ({ module: r.module.replace(/_/g, '-'), clouds: r.clouds ?? clouds, why: r.why })),
          after: m.afterOn,
          uses: m.uses,
        })),
      },
      null,
      2,
    )}\n`,
    { headers: { 'Content-Type': 'application/json' } },
  );
