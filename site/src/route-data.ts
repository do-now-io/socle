// Two corrections to every documentation page's route data:
// - the edit link points at the page in docs/, not at the src/content/docs
//   symlink the site reads it through;
// - the banner of a build that is not the last release (src/channel.ts), so
//   a page read under /socle/dev/ or a preview never passes for released
//   documentation. A page's own `banner` frontmatter still wins.
import { defineRouteMiddleware } from '@astrojs/starlight/route-data';
import { bannerHtml } from './channel';

export const onRequest = defineRouteMiddleware((context) => {
  const route = context.locals.starlightRoute;
  if (route.editUrl) route.editUrl = new URL(route.editUrl.href.replace('/site/src/content/docs/', '/docs/'));
  const content = bannerHtml();
  if (content && !route.entry.data.banner) route.entry.data.banner = { content };
});
