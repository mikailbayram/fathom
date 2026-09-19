# frozen_string_literal: true

# The snippet a salesperson pastes into a prospect's own console.
#
#   <script src="https://.../d/acme-a8f31c/widget.js" async></script>
#
# It puts the demo on the prospect's own website, which is the whole point:
# seeing your own site answer a question your own site could not answer is a
# more convincing argument than any deck.
#
# It has to run on a page we know nothing about, so it declares no globals
# beyond one guard, styles everything inline, and speaks to the page only
# through an iframe on our origin.
class WidgetScript
  def initialize(chatbot, origin:)
    @chatbot = chatbot
    @origin = origin
  end

  def to_js
    <<~JS
      (function () {
        if (window.__fathomWidget) return;
        window.__fathomWidget = true;

        var ORIGIN = #{@origin.to_json};
        var SLUG = #{@chatbot.slug.to_json};
        var NAME = #{@chatbot.name.to_json};
        var KEY = 'fathom.visitor.' + SLUG;

        // A visitor id the iframe can be told, because a third-party iframe
        // gets no cookie from us.
        var visitor = null;
        try { visitor = localStorage.getItem(KEY); } catch (e) {}
        if (!visitor) {
          visitor = (crypto.randomUUID && crypto.randomUUID()) ||
            'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
              var r = (Math.random() * 16) | 0;
              return (c === 'x' ? r : ((r & 0x3) | 0x8)).toString(16);
            });
          try { localStorage.setItem(KEY, visitor); } catch (e) {}
        }

        var open = false;

        var panel = document.createElement('iframe');
        panel.src = ORIGIN + '/d/' + SLUG + '?embed=1&v=' + encodeURIComponent(visitor);
        panel.title = 'Ask anything about ' + NAME;
        panel.setAttribute('allow', 'clipboard-write');
        style(panel, {
          position: 'fixed', bottom: '88px', right: '20px', width: 'min(400px, calc(100vw - 40px))',
          height: 'min(600px, calc(100vh - 130px))', border: '1px solid rgba(0,0,0,.10)',
          borderRadius: '16px', boxShadow: '0 12px 40px rgba(0,0,0,.16)', background: '#fff',
          zIndex: '2147483646', display: 'none', opacity: '0', transform: 'translateY(8px)',
          transition: 'opacity .18s ease, transform .18s ease', colorScheme: 'light'
        });

        var button = document.createElement('button');
        button.type = 'button';
        button.setAttribute('aria-label', 'Ask anything about ' + NAME);
        button.innerHTML = bubbleIcon();
        style(button, {
          position: 'fixed', bottom: '20px', right: '20px', width: '52px', height: '52px',
          borderRadius: '999px', border: 'none', background: '#111', color: '#fff', cursor: 'pointer',
          boxShadow: '0 8px 24px rgba(0,0,0,.22)', zIndex: '2147483647', display: 'flex',
          alignItems: 'center', justifyContent: 'center', padding: '0',
          transition: 'transform .15s ease'
        });
        button.onmouseenter = function () { button.style.transform = 'scale(1.05)'; };
        button.onmouseleave = function () { button.style.transform = 'scale(1)'; };

        button.onclick = function () {
          open = !open;
          button.innerHTML = open ? closeIcon() : bubbleIcon();
          if (open) {
            panel.style.display = 'block';
            requestAnimationFrame(function () {
              panel.style.opacity = '1';
              panel.style.transform = 'translateY(0)';
            });
          } else {
            panel.style.opacity = '0';
            panel.style.transform = 'translateY(8px)';
            setTimeout(function () { if (!open) panel.style.display = 'none'; }, 180);
          }
        };

        document.addEventListener('keydown', function (event) {
          if (event.key === 'Escape' && open) button.click();
        });

        function style(el, rules) {
          for (var key in rules) el.style[key] = rules[key];
        }

        function bubbleIcon() {
          return '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
            'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
            '<path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>';
        }

        function closeIcon() {
          return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
            'stroke-width="2.5" stroke-linecap="round" aria-hidden="true">' +
            '<path d="M18 6 6 18M6 6l12 12"/></svg>';
        }

        function mount() {
          document.body.appendChild(panel);
          document.body.appendChild(button);
        }

        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', mount);
        } else {
          mount();
        }
      })();
    JS
  end
end
