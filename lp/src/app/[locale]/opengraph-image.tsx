import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";
import { routing } from "@/i18n/routing";

export const alt = "Owler";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

/* ビルド時に焼く。動的なままだと public/ が関数側に含まれず、
   本番で icon.png を読めずに 500 になる */
export function generateStaticParams(): { locale: string }[] {
  return routing.locales.map((locale) => ({ locale }));
}

/* 出るのは kk-web の一覧で176px、X のカードで500px 前後。
   その大きさで残るのはアイコンと名前と1行だけ。色はアイコンから取る */
const NIGHT = "#0b0f2e";
const AMBER = "#ffb23e";
const WHITE = "#f5f6ff";

export default async function OgImage({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<ImageResponse> {
  const { locale } = await params;
  const isJa = locale === "ja";
  /* 見出しの書体はサイトと同じ Dela Gothic One。使う文字だけに絞ったものを
     同梱している。文言を変えたら assets/README.md の手順で作り直す */
  const [icon, font] = await Promise.all([
    readFile(join(process.cwd(), "public/icon.png")),
    readFile(join(process.cwd(), "assets/DelaGothicOne-subset.ttf")),
  ]);
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;

  return new ImageResponse(
    <div
      style={{
        alignItems: "center",
        /* 地をアイコンと同じ色にすると、アイコンの輪郭が溶けて消える。
           濃い地に、アイコンの藍と目の琥珀を光として置く */
        background: NIGHT,
        backgroundImage:
          "radial-gradient(55% 70% at 12% 20%, rgba(59,76,202,0.55) 0%, rgba(11,15,46,0) 62%), radial-gradient(60% 70% at 95% 95%, rgba(255,178,62,0.30) 0%, rgba(11,15,46,0) 60%)",
        display: "flex",
        gap: 56,
        height: "100%",
        justifyContent: "center",
        width: "100%",
      }}
    >
      {/* biome-ignore lint/performance/noImgElement: next/image is not available in ImageResponse */}
      <img alt="" height={250} src={iconSrc} width={250} />
      <div style={{ display: "flex", flexDirection: "column" }}>
        <div style={{ color: WHITE, fontSize: 118 }}>Owler</div>
        <div style={{ color: AMBER, display: "flex", fontSize: 34, marginTop: 14 }}>
          {isJa ? "定期実行を、エディタで見張る。" : "Your scheduled jobs, watched."}
        </div>
      </div>
    </div>,
    {
      ...size,
      fonts: [{ data: font, name: "Dela Gothic One", style: "normal", weight: 400 }],
    },
  );
}
