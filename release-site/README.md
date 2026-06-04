# MagicMusicCRM Legal Site

Static public legal pages for Google Play and App Store release metadata.

## Pages

- `/privacy/` - privacy policy
- `/terms/` - terms of use
- `/account-deletion/` - public account deletion instructions

## Deploy

```sh
npx vercel@latest release-site --prod
```

Use the production `/account-deletion/` URL in Google Play Console.

Current production alias:

- `https://magicmusiccrm-legal.vercel.app/`
