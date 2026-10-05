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
        // Decision records (docs/decisions/): see decisions/template.md.
        status: z.enum(['proposed', 'accepted', 'superseded']).optional(),
        date: z.coerce.date().optional(),
        cloud: z.enum(['aws', 'gcp', 'azure', 'scaleway', 'all']).optional(),
        supersededBy: z.string().optional(),
      }),
    }),
  }),
};
