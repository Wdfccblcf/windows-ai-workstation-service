import type { Metadata } from "next";
import "./globals.css";

const basePath = process.env.NEXT_PUBLIC_BASE_PATH || "";

export const metadata: Metadata = {
  metadataBase: new URL("https://wdfccblcf.github.io/windows-ai-workstation-service/"),
  title: {
    default: "Windows AI 环境搭建与排错",
    template: "%s｜Windows AI 环境搭建与排错",
  },
  description:
    "面向 Windows 11 新手的 AI 编程环境体检、标准搭建与完整搭建服务。平台担保，客户全程在场，先审计再修复。",
  icons: {
    icon: basePath + "/favicon.svg",
    shortcut: basePath + "/favicon.svg",
  },
  openGraph: {
    title: "Windows AI 环境搭建与排错",
    description: "先体检，再动手。平台担保的 Windows 11 AI 编程环境服务。",
    type: "website",
    locale: "zh_CN",
    images: [basePath + "/social-preview.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
