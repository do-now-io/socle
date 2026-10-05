// Two corrections to every page's route data:
// - the edit link points at the page in docs/, not at the src/content/docs
//   symlink the site reads it through;
// - a site-wide banner on every build that is not the last release, so a
//   page read under /socle/dev/ (or a preview) never passes for released
//   documentation. A page's own `banner` frontmatter still wins.
import { defineRouteMiddleware } from '@astrojs/starlight/route-data';

const channel = import.meta.env.SOCLE_CHANNEL ?? 'dev';
const released = import.meta.env.SOCLE_RELEASED === 'true';

export const onRequest = defineRouteMiddleware((context) => {
  const route = context.locals.starlightRoute;
  if (route.editUrl) route.editUrl = new URL(route.editUrl.href.replace('/site/src/content/docs/', '/docs/'));
  const { entry } = route;
  if (entry.data.banner) return;
  if (channel === 'dev') {
    entry.data.banner = {
      content: released
        ? 'You are reading <strong>dev</strong>: the documentation of <code>main</code>, not yet released. <a href="/socle/">Read the last release</a>.'
        : 'You are reading <strong>dev</strong>: the documentation of <code>main</code>. Nothing has been released yet.',
    };
  } else if (!released) {
    entry.data.banner = {
      content: 'Nothing has been released yet: this is the documentation of <code>main</code>.',
    };
  }
});
