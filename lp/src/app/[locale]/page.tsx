import Image from "next/image";
import { getTranslations, setRequestLocale } from "next-intl/server";
import type { ReactNode } from "react";
import { Link } from "@/i18n/navigation";
import { LanguageSwitch } from "./language-switch";

const REPO = "https://github.com/piro0919/owler";
const DOWNLOAD = `${REPO}/releases/latest`;
const BREW = "brew install --cask piro0919/tap/owler";

type Step = { title: string; body: string };

type PageProps = {
  params: Promise<{ locale: string }>;
};

function DownloadButton({ children }: { children: ReactNode }) {
  return (
    <a
      className="inline-block rounded-full bg-white px-9 py-4 font-extrabold text-[var(--color-navy)] shadow-[0_10px_0_0_rgba(8,10,40,0.35)] transition active:translate-y-1 active:shadow-[0_4px_0_0_rgba(8,10,40,0.35)]"
      href={DOWNLOAD}
    >
      {children}
    </a>
  );
}

/// ターミナルに貼る1行。横に長いので、狭い画面では中で横に流す
function Command({ children }: { children: string }) {
  return (
    <pre className="overflow-x-auto rounded-2xl bg-black/40 px-5 py-4 text-left font-mono text-[13px] text-white/90 leading-relaxed">
      <code>{children}</code>
    </pre>
  );
}

export default async function Page({ params }: PageProps) {
  const { locale } = await params;
  setRequestLocale(locale);

  const t = await getTranslations();
  const flow = t.raw("flow.steps") as Step[];
  const install = t.raw("install.steps") as Step[];
  const features = ["records", "claude", "editor", "add", "menubar"] as const;
  const shot = locale === "ja" ? "/shot-ja.png" : "/shot-en.png";

  return (
    <>
      {/* 見出し */}
      <section className="sky relative overflow-hidden px-6 pt-16 pb-24 text-white">
        <div className="dive" />
        <div className="relative mx-auto flex max-w-5xl flex-col items-center gap-14 lg:flex-row">
          <div className="flex flex-1 flex-col items-center gap-6 text-center lg:items-start lg:text-left">
            <div className="flex items-center gap-3">
              <span className="rounded-full bg-white/20 px-4 py-1 font-bold text-sm backdrop-blur">
                macOS
              </span>
              <LanguageSwitch />
            </div>
            <div className="flex items-center gap-4">
              <Image
                alt=""
                className="h-16 w-16 drop-shadow-lg"
                height={128}
                priority
                src="/icon.png"
                width={128}
              />
              <span className="display text-4xl">Owler</span>
            </div>
            <h1 className="display text-balance text-4xl leading-[1.3] sm:text-5xl">
              {t("hero.tagline")}
            </h1>
            <p className="max-w-md text-lg text-white/90 leading-relaxed">{t("hero.lead")}</p>
            <div className="flex flex-col items-center gap-3 lg:items-start">
              <DownloadButton>{t("hero.download")}</DownloadButton>
              <p className="text-sm text-white/75">{t("hero.requirement")}</p>
            </div>
          </div>

          <div className="flex flex-1 justify-center">
            <Image
              alt=""
              className="w-full max-w-xl rounded-2xl shadow-[0_30px_70px_-20px_rgba(5,8,40,0.6)] ring-4 ring-white/30"
              height={1200}
              priority
              src={shot}
              width={1920}
            />
          </div>
        </div>
      </section>

      {/* 流れ */}
      <section className="px-6 py-20">
        <div className="mx-auto flex max-w-5xl flex-col gap-12">
          <h2 className="display text-center text-3xl">{t("flow.title")}</h2>
          <ol className="grid gap-6 sm:grid-cols-3">
            {flow.map((step, index) => (
              <li
                className="flex flex-col gap-3 rounded-[28px] border-2 border-[var(--color-line)] bg-white p-7 shadow-sm"
                key={step.title}
              >
                <span className="display flex h-11 w-11 items-center justify-center rounded-full bg-[var(--color-indigo)] text-white text-xl">
                  {index + 1}
                </span>
                <h3 className="font-extrabold text-lg">{step.title}</h3>
                <p className="leading-relaxed opacity-75">{step.body}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* できること */}
      <section className="bg-[var(--color-mist-deep)] px-6 py-20">
        <div className="mx-auto flex max-w-5xl flex-col gap-12">
          <h2 className="display text-center text-3xl">{t("features.title")}</h2>
          <div className="grid gap-6 sm:grid-cols-2">
            {features.map((key, index) => (
              <div
                className={`flex flex-col gap-3 rounded-[28px] bg-white p-8 shadow-sm ${
                  // 数が奇数なら、最後の1つを横いっぱいに置いて半端を残さない
                  features.length % 2 === 1 && index === features.length - 1 ? "sm:col-span-2" : ""
                }`}
                key={key}
              >
                <h3 className="font-extrabold text-xl">{t(`features.${key}.title`)}</h3>
                <p className="leading-relaxed opacity-75">{t(`features.${key}.body`)}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* 入れ方 */}
      <section className="relative overflow-hidden bg-[var(--color-night)] px-6 py-20 text-white">
        <div className="relative mx-auto flex max-w-3xl flex-col gap-10">
          <h2 className="display text-center text-3xl">{t("install.title")}</h2>
          <ol className="flex flex-col gap-8">
            {install.map((step, index) => (
              <li className="flex gap-5" key={step.title}>
                <span className="display flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-[var(--color-indigo)] text-lg">
                  {index + 1}
                </span>
                <div className="flex min-w-0 flex-1 flex-col gap-3">
                  <h3 className="font-extrabold text-lg">{step.title}</h3>
                  <p className="text-white/80 leading-relaxed">{step.body}</p>
                  {index === 0 && <Command>{BREW}</Command>}
                </div>
              </li>
            ))}
          </ol>
          <p className="text-center text-sm text-white/70 leading-relaxed">
            {t("install.accessibility")}
          </p>
          <div className="flex justify-center">
            <DownloadButton>{t("install.cta")}</DownloadButton>
          </div>
        </div>
      </section>

      <footer className="flex justify-center gap-6 bg-[var(--color-mist)] px-6 py-10 text-sm">
        <a className="font-semibold opacity-60 hover:opacity-100" href={REPO}>
          {t("footer.source")}
        </a>
        <a className="font-semibold opacity-60 hover:opacity-100" href={`${REPO}/releases`}>
          {t("footer.releases")}
        </a>
        <Link className="font-semibold opacity-60 hover:opacity-100" href="/privacy">
          {t("footer.privacy")}
        </Link>
      </footer>
    </>
  );
}
