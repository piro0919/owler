# assets

`DelaGothicOne-subset.ttf` is the face drawn into the Open Graph card
(`src/app/[locale]/opengraph-image.tsx`). It is the same display face the site
uses for its headings, cut down to the characters the card actually shows.

Any character missing from it silently falls back to a different face, so when
the card's copy changes, rebuild the subset:

```sh
curl -sL -o /tmp/DelaGothicOne-Regular.ttf \
  "https://github.com/google/fonts/raw/main/ofl/delagothicone/DelaGothicOne-Regular.ttf"

pyftsubset /tmp/DelaGothicOne-Regular.ttf \
  --text="Owler Your scheduled jobs, watched. 定期実行を、エディタで見張る。" \
  --unicodes="U+0020-007E" \
  --output-file=assets/DelaGothicOne-subset.ttf \
  --no-hinting --desubroutinize --layout-features=''
```
