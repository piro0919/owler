# assets

The faces drawn into the Open Graph card (`src/app/[locale]/opengraph-image.tsx`),
cut down to the characters the card shows: Geist SemiBold for the Latin text and
Noto Sans JP SemiBold for the Japanese line. The site itself uses the same faces
through `next/font`.

A character missing from a subset falls back to a different face, so when the
card's copy changes, fetch the subsets again. Google Fonts cuts them with the
`text` parameter; an old user agent makes it serve WOFF, which the card can read.

```sh
UA="Mozilla/5.0 (Windows NT 6.1) AppleWebKit/534.30 (KHTML, like Gecko) Safari/534.30"
curl -s -A "$UA" "https://fonts.googleapis.com/css2?family=Geist:wght@600&text=<url-encoded text>"
curl -s -A "$UA" "https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@600&text=<url-encoded text>"
# download the url(...) in each response into assets/
```
