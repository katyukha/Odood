module odood.lib.assembly.source_provider;

/** Interface `Assembly` uses to obtain the files of its sources and standalone
  * addons before scanning/copying them into dist. Default: AssemblySourceProviderCached.
  **/

private import thepath: Path;

private import odood.utils.odoo.serie: OdooSerie;
private import odood.lib.assembly.spec: AssemblySpecSource, AssemblySpecAddon;


/** Strategy for materializing an assembly's sources and standalone addons.
  *
  * Init/teardown are the owner's responsibility, not this interface's: `Assembly`
  * only resolves paths and copies out of them during `sync()`, never keeping a
  * path afterward — so a worktree-style provider can be torn down once sync returns.
  **/
interface AssemblySourceProviderInterface {

    /** Materialize all listed sources at their required ref/commit ahead of
      * `resolveSource`, with whatever concurrency the provider prefers. Idempotent
      * hint — MAY be a no-op; correctness comes from `resolveSource`. Providers own
      * thread-safety here; `resolveSource` is called sequentially.
      **/
    void ensureSources(in AssemblySpecSource[] sources, in OdooSerie serie);

    /** Local path to a source's tree (materialized on first need) for the assembly
      * to scan and copy addons from. Idempotent. **/
    Path resolveSource(in AssemblySpecSource source, in OdooSerie serie);

    /** Local path to an addon no source supplies, resolved by name from an external
      * registry (Odoo Apps in the cached provider). Idempotent. **/
    Path resolveExternalAddon(in AssemblySpecAddon specAddon, in OdooSerie serie);
}
