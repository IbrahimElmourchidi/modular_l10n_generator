// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const repo = 'https://github.com/IbrahimElmourchidi/modular_l10n_generator';

// The public address of the site, used for canonical links and the sitemap.
// The GitHub Pages workflow sets SITE_URL from the DOCS_URL repository
// variable; the custom domain itself is set in Settings → Pages.
const site = process.env.SITE_URL || 'https://l10n.utanium.org';

export default defineConfig({
	site,
	integrations: [
		starlight({
			title: 'Modular L10n',
			description:
				'Modular, type-safe Flutter localization from the command line or a terminal GUI. Only Dart required.',
			logo: { src: './src/assets/logo.svg', alt: 'Modular L10n' },
			favicon: '/favicon.svg',
			customCss: ['./src/styles/theme.css'],
			social: [
				{ icon: 'github', label: 'GitHub', href: repo },
				{ icon: 'external', label: 'pub.dev', href: 'https://pub.dev/packages/modular_l10n_generator' },
			],
			editLink: { baseUrl: `${repo}/edit/main/website/` },
			lastUpdated: true,
			sidebar: [
				{
					label: 'Start here',
					items: [
						{ label: 'Getting started', slug: 'getting-started' },
						{ label: 'The terminal GUI', slug: 'gui' },
					],
				},
				{
					label: 'Guides',
					items: [
						{ label: 'Writing ARB files', slug: 'guides/arb-files' },
						{ label: 'Using the generated code', slug: 'guides/generated-code' },
						{ label: 'Modules, keys and locales', slug: 'guides/modules-keys-locales' },
						{ label: 'Working with translators', slug: 'guides/translators' },
						{ label: 'Finding hardcoded text', slug: 'guides/hardcoded-text' },
						{ label: 'Keeping translations healthy', slug: 'guides/quality' },
						{ label: 'Migrating from Flutter Intl', slug: 'guides/migrate-flutter-intl' },
						{ label: 'Android Studio and IntelliJ', slug: 'guides/android-studio' },
						{ label: 'CI', slug: 'guides/ci' },
						{ label: 'Coming from the VS Code extension', slug: 'guides/vscode-extension' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Commands', slug: 'reference/commands' },
						{ label: 'Configuration', slug: 'reference/configuration' },
						{ label: 'GUI keys', slug: 'reference/gui-keys' },
						{ label: 'Library API', slug: 'reference/library' },
					],
				},
			],
		}),
	],
});
