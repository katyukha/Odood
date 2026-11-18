// Loaded only by the PDF build (.github/workflows/release.yml), not the site.
// mdBook's print.html calls window.print() once loaded; in headless Chrome
// that print races mdbook-pdf's own request, which then fails with "Page is
// already being printed".
if (window.location.pathname.endsWith("/print.html"))
    window.print = function() {};
