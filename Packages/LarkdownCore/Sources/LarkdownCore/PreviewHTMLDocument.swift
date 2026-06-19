import Foundation

public enum PreviewHTMLDocument {
    public static func make(body: String) -> String {
        let nonce = UUID().uuidString
        let scheme = PreviewResource.scheme
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(scheme): data: https: http:; media-src \(scheme): data: https: http:; style-src 'nonce-\(nonce)'; script-src 'nonce-\(nonce)'; base-uri 'none'; form-action 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style nonce="\(nonce)">
        \(style)
        \(highlightStyle)
        </style>
        </head>
        <body>
        <main class="markdown-body">
        \(body)
        </main>
        <script nonce="\(nonce)">
        \(highlightJavaScript)
        \(script)
        </script>
        </body>
        </html>
        """
    }

    private static let style = """
    :root {
      color-scheme: light dark;
      --body: Canvas;
      --text: CanvasText;
      --muted: color-mix(in srgb, CanvasText 62%, Canvas);
      --border: color-mix(in srgb, CanvasText 18%, Canvas);
      --code-bg: color-mix(in srgb, CanvasText 7%, Canvas);
      --link: LinkText;
      --quote: color-mix(in srgb, CanvasText 48%, Canvas);
    }
    html, body {
      background: var(--body);
      color: var(--text);
      margin: 0;
      padding: 0;
    }
    body {
      font: 15px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    .markdown-body {
      box-sizing: border-box;
      max-width: 920px;
      margin: 0 auto;
      padding: 28px 34px 48px;
    }
    h1, h2, h3, h4, h5, h6 {
      line-height: 1.25;
      margin: 24px 0 12px;
      font-weight: 650;
    }
    h1, h2 { border-bottom: 1px solid var(--border); padding-bottom: 0.25em; }
    h1 { font-size: 2em; }
    h2 { font-size: 1.5em; }
    h3 { font-size: 1.25em; }
    p, ul, ol, blockquote, pre, table { margin: 0 0 16px; }
    a { color: var(--link); }
    blockquote {
      color: var(--quote);
      border-left: 4px solid var(--border);
      padding: 0 1em;
    }
    code, pre {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 0.92em;
    }
    code {
      background: var(--code-bg);
      border-radius: 4px;
      padding: 0.12em 0.32em;
    }
    pre {
      background: var(--code-bg);
      border-radius: 6px;
      overflow: auto;
      padding: 14px 16px;
    }
    pre code { background: transparent; padding: 0; }
    table {
      border-collapse: collapse;
      width: 100%;
      display: block;
      overflow-x: auto;
    }
    th, td {
      border: 1px solid var(--border);
      padding: 6px 10px;
    }
    th { font-weight: 650; }
    hr { border: 0; border-top: 1px solid var(--border); margin: 24px 0; }
    img { max-width: 100%; height: auto; }
    li:has(> input[type="checkbox"]) { list-style: none; }
    li > input[type="checkbox"] { margin: 0 0.45em 0 -1.4em; }
    sup { line-height: 0; }
    section.footnotes {
      border-top: 1px solid var(--border);
      font-size: 0.9em;
      margin-top: 24px;
    }
    """

    private static let highlightStyle = """
    \(resource(named: "github.min", extension: "css", subdirectory: "highlightjs"))
    @media (prefers-color-scheme: dark) {
      \(resource(named: "github-dark.min", extension: "css", subdirectory: "highlightjs"))
    }
    """

    private static let highlightJavaScript = resource(named: "highlight.min", extension: "js", subdirectory: "highlightjs")

    private static func resource(named name: String, extension fileExtension: String, subdirectory: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension)

        guard let url,
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }

        return value
    }

    private static let script = """
    if (window.hljs) {
      hljs.highlightAll();
    }

    window.larkdownHighlightPreview = function(root) {
      if (!window.hljs) { return; }
      const scope = root || document;
      scope.querySelectorAll('pre code').forEach((code) => {
        code.removeAttribute('data-highlighted');
        code.classList.remove('hljs');
        hljs.highlightElement(code);
      });
    };

    window.larkdownAssignHeadingIDs = function() {
      document.querySelectorAll('[data-larkdown-id]').forEach((heading) => {
        heading.removeAttribute('id');
        heading.removeAttribute('data-larkdown-id');
      });

      const used = new Map();
      document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((heading) => {
        if (heading.id) { return; }
        const base = heading.textContent
          .toLowerCase()
          .replace(/[^\\p{L}\\p{M}\\p{N}\\p{Pc}\\- ]/gu, '')
          .replace(/ /g, '-');
        const count = used.get(base) || 0;
        used.set(base, count + 1);
        heading.id = count === 0 ? base : base + '-' + count;
        heading.setAttribute('data-larkdown-id', '');
      });
    };

    window.larkdownAssignHeadingIDs();

    window.larkdownUpdatePreviewBody = function(htmlBody, line, scrollFraction, isAtBottom) {
      const main = document.querySelector('main.markdown-body');
      if (!main) { return; }

      const template = document.createElement('template');
      template.innerHTML = htmlBody;
      const nextNodes = Array.from(template.content.childNodes);
      const changedNodes = [];
      let index = 0;

      while (index < nextNodes.length || index < main.childNodes.length) {
        const current = main.childNodes[index];
        const next = nextNodes[index];

        if (!next) {
          current.remove();
          continue;
        }

        if (!current) {
          const inserted = main.appendChild(next);
          if (inserted.nodeType === Node.ELEMENT_NODE) {
            changedNodes.push(inserted);
          }
          index += 1;
          continue;
        }

        if (current.isEqualNode(next)) {
          index += 1;
          continue;
        }

        const inserted = main.insertBefore(next, current);
        current.remove();
        if (inserted.nodeType === Node.ELEMENT_NODE) {
          changedNodes.push(inserted);
        }
        index += 1;
      }

      changedNodes.forEach((node) => window.larkdownHighlightPreview(node));
      window.larkdownAssignHeadingIDs();
      if (line !== null && line !== undefined && window.larkdownScrollToPosition) {
        window.larkdownScrollToPosition(line, scrollFraction, isAtBottom, false);
      }
    };

    (function() {
      let animationFrame = null;
      let targetScrollY = 0;
      const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

      function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(value, maximum));
      }

      function scrollRoot() {
        return document.scrollingElement || document.documentElement;
      }

      function maxScrollY() {
        return Math.max(0, scrollRoot().scrollHeight - window.innerHeight);
      }

      function animateTowardTarget() {
        animationFrame = null;
        const maximum = maxScrollY();
        const target = clamp(targetScrollY, 0, maximum);
        const current = window.scrollY;
        const delta = target - current;

        if (Math.abs(delta) < 0.75) {
          window.scrollTo({ top: target, behavior: 'auto' });
          return;
        }

        window.scrollTo({ top: current + (delta * 0.32), behavior: 'auto' });
        animationFrame = window.requestAnimationFrame(animateTowardTarget);
      }

      function setPreviewScrollTarget(target, animated) {
        targetScrollY = clamp(target, 0, maxScrollY());

        if (!animated || reduceMotion) {
          if (animationFrame) {
            window.cancelAnimationFrame(animationFrame);
            animationFrame = null;
          }
          window.scrollTo({ top: targetScrollY, behavior: 'auto' });
          return;
        }

        if (!animationFrame) {
          animationFrame = window.requestAnimationFrame(animateTowardTarget);
        }
      }

      // cmark writes data-sourcepos as "startLine:column-endLine:column".
      function sourceLine(block) {
        return parseInt(block.dataset.sourcepos, 10) || 1;
      }

      function targetForSourcePosition(line, scrollFraction, isAtBottom) {
        const blocks = Array.from(document.querySelectorAll('[data-sourcepos]'));
        const maximum = maxScrollY();

        if (isAtBottom || scrollFraction >= 0.995) {
          return maximum;
        }

        if (blocks.length === 0) {
          return maximum * clamp(scrollFraction, 0, 1);
        }

        let previous = blocks[0];
        let next = null;
        for (const block of blocks) {
          const start = sourceLine(block);
          if (start <= line) {
            previous = block;
          } else {
            next = block;
            break;
          }
        }

        const previousLine = sourceLine(previous);
        const previousTop = previous.getBoundingClientRect().top + window.scrollY;
        let targetTop = previousTop;

        if (next) {
          const nextLine = sourceLine(next);
          const nextTop = next.getBoundingClientRect().top + window.scrollY;
          const denominator = Math.max(1, nextLine - previousLine);
          const localProgress = clamp((line - previousLine) / denominator, 0, 1);
          targetTop = previousTop + ((nextTop - previousTop) * localProgress);
        } else {
          const proportionalTop = maximum * clamp(scrollFraction, 0, 1);
          targetTop = Math.max(previousTop, proportionalTop);
        }

        return clamp(targetTop, 0, maximum);
      }

      window.larkdownScrollToPosition = function(line, scrollFraction, isAtBottom, animated) {
        setPreviewScrollTarget(
          targetForSourcePosition(line, scrollFraction, isAtBottom),
          animated
        );
      };
    })();
    """
}
