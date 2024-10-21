module odood.lib.addons.repository;

private import std.logger: warningf, infof;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.exception: OdoodException;
private import odood.git: GitRepository;


// TODO: Do we need this class?
class AddonRepository : GitRepository{
    private const Project _project;

    @disable this();

    this(in Project project, in Path path) {
        super(path);
        _project = project;
    }

    this(in Project project, in GitRepository repo) {
        super(repo.path);
        _project = project;
    }

    /** Return Odood project associated with this addons repository
      **/
    auto project() const => _project;

    /** Scan repository for addons and return array of odoo addons,
      * found in this repo.
      * This method searches for addons recursively by default.
      *
      * Params:
      *     recursive = If set to true, search for addons recursively inside repo.
      *         Otherwise, scan only the root directory of the repo for addons.
      **/
    auto addons(in bool recursive=true) const {
        return project.addons.scan(path, recursive);
    }
}
