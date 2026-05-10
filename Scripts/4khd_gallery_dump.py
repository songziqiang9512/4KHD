#!/usr/bin/env python3
import argparse
import json
import re
import ssl
import sys
import time
from html.parser import HTMLParser
from pathlib import Path
from typing import Dict, List
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen


USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/135.0.0.0 Safari/537.36"
)


class GalleryParser(HTMLParser):
    def __init__(self, base_url: str) -> None:
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.images: List[str] = []
        self.links: List[str] = []
        self.title_parts: List[str] = []
        self.in_title = False

    def handle_starttag(self, tag: str, attrs) -> None:
        attr_map = {k: v for k, v in attrs}
        if tag == "title":
            self.in_title = True
        elif tag == "img":
            src = attr_map.get("src") or attr_map.get("data-src")
            if src:
                self.images.append(urljoin(self.base_url, src))
        elif tag == "a":
            href = attr_map.get("href")
            if href:
                self.links.append(urljoin(self.base_url, href))

    def handle_data(self, data: str) -> None:
        text = data.strip()
        if text and self.in_title:
            self.title_parts.append(text)

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self.in_title = False


def build_request(url: str, referer: str = "") -> Request:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    }
    if referer:
        headers["Referer"] = referer
    return Request(url, headers=headers)


def fetch(url: str, timeout: float, referer: str = "") -> Dict[str, object]:
    last_error = None
    for attempt in range(3):
        try:
            request = build_request(url, referer=referer)
            with urlopen(request, timeout=timeout, context=ssl.create_default_context()) as response:
                body = response.read()
                return {
                    "status": getattr(response, "status", None) or response.getcode(),
                    "final_url": response.geturl(),
                    "headers": dict(response.headers.items()),
                    "body": body,
                }
        except URLError as exc:
            last_error = exc
            if "EOF occurred in violation of protocol" not in str(exc.reason) or attempt == 2:
                raise
            time.sleep(0.6 * (attempt + 1))
    if last_error:
        raise last_error
    raise RuntimeError("fetch failed without error")


def decode_body(body: bytes, headers: Dict[str, str]) -> str:
    content_type = headers.get("Content-Type", "")
    match = re.search(r"charset=([^\s;]+)", content_type, flags=re.IGNORECASE)
    encoding = match.group(1).strip("\"'") if match else "utf-8"
    aliases = {"utf8mb4": "utf-8", "utf8": "utf-8"}
    encoding = aliases.get(encoding.lower(), encoding)
    return body.decode(encoding, errors="replace")


def dedupe(items: List[str]) -> List[str]:
    seen = set()
    out = []
    for item in items:
        if not item or item in seen:
            continue
        seen.add(item)
        out.append(item)
    return out


def extract_gallery_pages(page_url: str, links: List[str]) -> List[str]:
    base = page_url.rstrip("/")
    pages = []
    for href in dedupe(links):
        href = href.rstrip("/")
        if href.startswith(base + "/") and re.search(r"/\d+$", href):
            pages.append(href)
    return dedupe(pages)


def filter_gallery_images(images: List[str], slug_hint: str) -> List[str]:
    out = []
    for src in dedupe(images):
        if "i0.wp.com/pic.4khd.com/" not in src:
            continue
        if slug_hint not in src:
            continue
        out.append(src)
    return out


def dump_gallery(url: str, timeout: float) -> Dict[str, object]:
    first = fetch(url, timeout=timeout, referer="https://www.4khd.com/")
    html = decode_body(first["body"], first["headers"])
    parser = GalleryParser(str(first["final_url"]))
    parser.feed(html)
    title = " ".join(parser.title_parts).strip()

    slug_match = re.search(r"/content/\d+/([^.]+)\.html", str(first["final_url"]))
    slug = slug_match.group(1) if slug_match else ""

    page_urls = [str(first["final_url"])]
    page_urls.extend(extract_gallery_pages(str(first["final_url"]), parser.links))

    pages = []
    all_images: List[str] = []
    for page_url in page_urls:
        result = fetch(page_url, timeout=timeout, referer=url)
        page_html = decode_body(result["body"], result["headers"])
        page_parser = GalleryParser(str(result["final_url"]))
        page_parser.feed(page_html)
        page_images = filter_gallery_images(page_parser.images, slug)
        pages.append(
            {
                "url": str(result["final_url"]),
                "title": " ".join(page_parser.title_parts).strip(),
                "image_count": len(page_images),
                "image_urls": page_images,
            }
        )
        all_images.extend(page_images)

    unique_images = dedupe(all_images)
    filenames = [urlparse(src).path.split("/")[-1] for src in unique_images]
    return {
        "requested_url": url,
        "final_url": str(first["final_url"]),
        "title": title,
        "slug": slug,
        "page_count": len(page_urls),
        "page_urls": page_urls,
        "total_unique_images": len(unique_images),
        "image_filenames": filenames,
        "image_urls": unique_images,
        "pages": pages,
    }


def main() -> int:
    argp = argparse.ArgumentParser(description="Dump all gallery image URLs from a 4khd content page.")
    argp.add_argument("--url", required=True)
    argp.add_argument("--timeout", type=float, default=20.0)
    argp.add_argument("--output-dir", default="Scripts/outputs/4khd_gallery_dump")
    args = argp.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    try:
        summary = dump_gallery(args.url, timeout=args.timeout)
    except HTTPError as exc:
        summary = {"requested_url": args.url, "error_type": "HTTPError", "status": exc.code, "reason": str(exc)}
        (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 1
    except URLError as exc:
        summary = {"requested_url": args.url, "error_type": "URLError", "reason": str(exc.reason)}
        (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 2
    except Exception as exc:
        summary = {"requested_url": args.url, "error_type": exc.__class__.__name__, "reason": str(exc)}
        (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 3

    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    (out_dir / "image_urls.txt").write_text("\n".join(summary["image_urls"]) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
