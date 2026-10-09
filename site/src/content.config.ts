// The docs collection is the repository's docs/: the content lives with the
// code, and this folder holds only the generator. src/content/docs is a
// symlink to it, because starlight-links-validator (and Starlight's
// conventions) expect the pages there; remark-socle resolves each page's
// links from its real path.
import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';
import { docsSchema } from '@astrojs/starlight/schema';
import { sections } from './sections.mjs';

export const collections = {
  docs: defineCollection({
    loader: glob({ base: './src/content/docs', pattern: sections.patterns }),
    schema: docsSchema({
      extend: z.object({
        // Catalog module pages (docs/catalog/<module>.md): see
        // docs/catalog/_template.md. They feed the generated catalog and its
        // dependency graph (#71, M3.5).
        category: z
          .enum(['networking', 'security', 'gitops', 'observability', 'autoscaling', 'secrets', 'backup', 'platform'])
          .optional(),
        requires: z
          .array(
            z.object({
              module: z.string(),
              clouds: z.array(z.enum(['aws', 'gcp', 'azure', 'scaleway'])).optional(),
              why: z.string(),
            }),
          )
          .optional(),
      }),
    }),
  }),
};
