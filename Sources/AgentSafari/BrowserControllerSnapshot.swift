import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    func snapshot() async throws -> [String: String] {
        let script = """
        (() => {
          if (!window.__agentSafariSnapshotRefs) {
            window.__agentSafariSnapshotRefs = new WeakMap();
            window.__agentSafariSnapshotNextRef = 1;
          }

          const refFor = (element) => {
            let ref = window.__agentSafariSnapshotRefs.get(element);
            if (!ref) {
              ref = `@e${window.__agentSafariSnapshotNextRef++}`;
              window.__agentSafariSnapshotRefs.set(element, ref);
            }
            return ref;
          };

          const cssEscape = (value) => {
            if (window.CSS && typeof window.CSS.escape === 'function') return window.CSS.escape(value);
            return String(value).replace(/[^a-zA-Z0-9_-]/g, '\\$&');
          };

          const selectorFor = (element) => {
            const tag = (element.tagName || '').toLowerCase();
            if (!tag) return '';
            if (element.id) return `${tag}#${cssEscape(element.id)}`;
            const name = element.getAttribute('name');
            if (name) return `${tag}[name="${String(name).replace(/"/g, '\\"')}"]`;
            const aria = element.getAttribute('aria-label');
            if (aria) return `${tag}[aria-label="${String(aria).replace(/"/g, '\\"')}"]`;
            const role = element.getAttribute('role');
            if (role) return `${tag}[role="${String(role).replace(/"/g, '\\"')}"]`;
            const classes = Array.from(element.classList || []).slice(0, 3).map(cssEscape);
            return classes.length ? `${tag}.${classes.join('.')}` : tag;
          };

          const textFor = (element) => {
            const tag = (element.tagName || '').toLowerCase();
            if (tag === 'input' || tag === 'textarea') {
              return (element.getAttribute('aria-label') || element.getAttribute('placeholder') || element.value || '').trim();
            }
            return (element.innerText || element.textContent || element.getAttribute('aria-label') || element.getAttribute('title') || '').replace(new RegExp('\\\\s+', 'g'), ' ').trim();
          };

          const labelTextFor = (element) => {
            const id = element.id;
            if (id) {
              const label = document.querySelector(`label[for="${cssEscape(id)}"]`);
              if (label) return textFor(label);
            }
            const wrappingLabel = element.closest && element.closest('label');
            return wrappingLabel ? textFor(wrappingLabel) : '';
          };

          const roleFor = (element) => {
            const explicit = element.getAttribute('role');
            if (explicit) return explicit;
            const tag = (element.tagName || '').toLowerCase();
            const type = (element.getAttribute('type') || '').toLowerCase();
            if (tag === 'a' && element.getAttribute('href')) return 'link';
            if (tag === 'button') return 'button';
            if (tag === 'select') return 'combobox';
            if (tag === 'textarea') return 'textbox';
            if (tag === 'input') {
              if (['button','submit','reset'].includes(type)) return 'button';
              if (type === 'checkbox') return 'checkbox';
              if (type === 'radio') return 'radio';
              if (type === 'range') return 'slider';
              return 'textbox';
            }
            if (element.isContentEditable) return 'textbox';
            return '';
          };

          const nameFor = (element) => {
            return element.getAttribute('aria-label') || element.getAttribute('title') || element.getAttribute('alt') || labelTextFor(element) || textFor(element) || element.getAttribute('name') || element.id || '';
          };

          const isCandidate = (element) => {
            const tag = (element.tagName || '').toLowerCase();
            if (['a', 'button', 'input', 'select', 'textarea', 'summary', 'label'].includes(tag)) return true;
            if (element.hasAttribute('role') || element.hasAttribute('onclick') || element.hasAttribute('contenteditable')) return true;
            const tabIndex = element.getAttribute('tabindex');
            return tabIndex !== null && Number(tabIndex) >= 0;
          };

          const isVisible = (element, rect) => {
            const style = window.getComputedStyle(element);
            return style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || '1') > 0 && rect.width > 0 && rect.height > 0;
          };

          const elements = Array.from(document.querySelectorAll('a,button,input,select,textarea,summary,label,[role],[onclick],[tabindex],[contenteditable]'));
          const snapshot = [];
          for (const [domIndex, element] of elements.entries()) {
            if (!isCandidate(element)) continue;
            const rect = element.getBoundingClientRect();
            if (!isVisible(element, rect)) continue;
            const style = window.getComputedStyle(element);
            const centerX = rect.left + rect.width / 2;
            const centerY = rect.top + rect.height / 2;
            const viewportIntersecting = rect.bottom >= 0 && rect.right >= 0 && rect.top <= window.innerHeight && rect.left <= window.innerWidth;
            const centerHit = viewportIntersecting ? document.elementFromPoint(Math.min(Math.max(centerX, 0), window.innerWidth - 1), Math.min(Math.max(centerY, 0), window.innerHeight - 1)) : null;
            const accessibleName = nameFor(element);
            const inferredRole = roleFor(element);
            snapshot.push({
              snapshotSchemaVersion: 2,
              ref: refFor(element),
              refSource: 'weakmap',
              domIndex,
              tag: (element.tagName || '').toLowerCase(),
              text: textFor(element).slice(0, 200),
              selector: selectorFor(element),
              role: inferredRole,
              explicitRole: element.getAttribute('role') || '',
              type: element.getAttribute('type') || '',
              name: element.getAttribute('name') || '',
              accessibleName: String(accessibleName || '').slice(0, 200),
              label: labelTextFor(element).slice(0, 200),
              ariaLabel: element.getAttribute('aria-label') || '',
              placeholder: element.getAttribute('placeholder') || '',
              href: element.href || element.getAttribute('href') || '',
              value: typeof element.value === 'string' ? element.value.slice(0, 200) : '',
              visible: true,
              disabled: Boolean(element.disabled || element.getAttribute('aria-disabled') === 'true'),
              editable: Boolean(element.isContentEditable || ['input','textarea','select'].includes((element.tagName || '').toLowerCase())),
              checked: Boolean(element.checked),
              selected: Boolean(element.selected),
              viewportIntersecting,
              zIndex: style.zIndex || '',
              occluded: Boolean(centerHit && centerHit !== element && !element.contains(centerHit)),
              center: { x: Math.round(centerX), y: Math.round(centerY) },
              framePath: 'main',
              shadowRoot: Boolean(element.shadowRoot),
              bounds: {
                x: Math.round(rect.x),
                y: Math.round(rect.y),
                width: Math.round(rect.width),
                height: Math.round(rect.height)
              }
            });
          }
          return JSON.stringify(snapshot.sort((left, right) => left.domIndex - right.domIndex));
        })()
        """
        let value = try await webView.evaluateJavaScript(script)
        return ["snapshot": stringifyJavaScriptValue(value as Any)]
    }
}
