// Which build this is (astro.config.mjs passes it in), and the banner every
// page of a build that is not the last release carries: the documentation
// pages through route-data.ts, the landing page directly.
export const channel: string = import.meta.env.SOCLE_CHANNEL ?? 'dev';
export const released = import.meta.env.SOCLE_RELEASED === 'true';
// The last release, even one tagged before this site existed.
export const release: string = import.meta.env.SOCLE_RELEASE ?? '';
const notes = (v: string) => `<a href="https://github.com/do-now-io/socle/releases/tag/${v}">${v}</a>`;
export const pr: string = import.meta.env.SOCLE_PR ?? '';

/** The banner's HTML, or undefined on the last release. */
export function bannerHtml(): string | undefined {
  if (channel === 'pr') {
    return `Preview of <a href="https://github.com/do-now-io/socle/pull/${pr}">pull request #${pr}</a>: not merged, not released. <a href="/socle/dev/">Read main</a>.`;
  }
  if (channel === 'dev') {
    return released
      ? 'You are reading <strong>dev</strong>: the documentation of <code>main</code>, not yet released. <a href="/socle/">Read the last release</a>.'
      : release
        ? `You are reading <strong>dev</strong>: the documentation of <code>main</code>. The last release, ${notes(release)}, predates this site.`
        : 'You are reading <strong>dev</strong>: the documentation of <code>main</code>. Nothing has been released yet.';
  }
  if (!released) {
    return release
      ? `The last release, ${notes(release)}, predates this site: this is the documentation of <code>main</code>.`
      : 'Nothing has been released yet: this is the documentation of <code>main</code>.';
  }
  return undefined;
}
