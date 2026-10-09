import { Analytics } from "@vercel/analytics/next";
import type { Metadata } from "next";
import { Geist, Geist_Mono, Noto_Sans_JP } from "next/font/google";
import { notFound } from "next/navigation";
import { hasLocale, NextIntlClientProvider } from "next-intl";
import { getTranslations, setRequestLocale } from "next-intl/server";
import type { ReactNode } from "react";
import { routing } from "@/i18n/routing";
import { languageAlternates, localePath, ogAlternateLocales, ogLocale } from "@/i18n/urls";
import "./globals.css";

// 手本は Vercel のトップページ。欧文は Geist、日本語は Noto Sans JP、コマンドは Geist Mono。
// 日本語の書体は unicode-range で100件以上に割られていて、先読みすると
// 1ページで1.5MB読む。preload を切って、使う字の分だけ取らせる
const sans = Geist({ display: "swap", subsets: ["latin"], variable: "--font-geist" });

const mono = Geist_Mono({ display: "swap", subsets: ["latin"], variable: "--font-geist-mono" });

const japanese = Noto_Sans_JP({
  display: "swap",
  preload: false,
  variable: "--font-noto-jp",
  weight: ["400", "500", "600", "700"],
});

type LayoutProps = {
  children: ReactNode;
  params: Promise<{ locale: string }>;
};

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({
  params,
}: Omit<LayoutProps, "children">): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "meta" });

  return {
    description: t("description"),
    alternates: {
      canonical: localePath(locale),
      languages: languageAlternates(),
    },
    metadataBase: new URL("https://owler.kkweb.io"),
    openGraph: {
      locale: ogLocale(locale),
      alternateLocale: ogAlternateLocales(locale),
      description: t("description"),
      url: localePath(locale),
      title: t("title"),
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      description: t("description"),
      title: t("title"),
    },
    title: t("title"),
  };
}

export default async function Layout({ children, params }: LayoutProps) {
  const { locale } = await params;

  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }
  setRequestLocale(locale);

  return (
    <html className={`${sans.variable} ${mono.variable} ${japanese.variable}`} lang={locale}>
      <body className="antialiased">
        <NextIntlClientProvider>{children}</NextIntlClientProvider>
        <Analytics />
      </body>
    </html>
  );
}
