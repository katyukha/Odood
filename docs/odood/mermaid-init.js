window.addEventListener('load', function () {
    var els = document.querySelectorAll('code.language-mermaid');
    if (els.length === 0) return;

    var script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js';
    script.onload = function () {
        mermaid.initialize({ startOnLoad: false, theme: 'neutral' });
        els.forEach(function (code) {
            var pre = code.parentElement;
            var div = document.createElement('div');
            div.className = 'mermaid';
            div.textContent = code.textContent;
            pre.parentElement.replaceChild(div, pre);
        });
        mermaid.run();
    };
    document.head.appendChild(script);
});
