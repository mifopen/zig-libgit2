const std = @import("std");
const raw = @import("internal/raw.zig");
const internal = @import("internal/internal.zig");
const log = std.log.scoped(.git);

const git = @import("git.zig");

pub const Repository = opaque {
    pub fn deinit(self: *Repository) void {
        log.debug("Repository.deinit called", .{});

        raw.git_repository_free(internal.toC(self));

        log.debug("repository closed successfully", .{});
    }

    pub fn state(self: *const Repository) RepositoryState {
        log.debug("Repository.state called", .{});

        const ret = @intToEnum(RepositoryState, raw.git_repository_state(internal.toC(self)));

        log.debug("repository state: {s}", .{@tagName(ret)});

        return ret;
    }

    pub const RepositoryState = enum(c_int) {
        NONE,
        MERGE,
        REVERT,
        REVERT_SEQUENCE,
        CHERRYPICK,
        CHERRYPICK_SEQUENCE,
        BISECT,
        REBASE,
        REBASE_INTERACTIVE,
        REBASE_MERGE,
        APPLY_MAILBOX,
        APPLY_MAILBOX_OR_REBASE,
    };

    /// Retrieve the configured identity to use for reflogs
    pub fn identityGet(self: *const Repository) !Identity {
        log.debug("Repository.identityGet called", .{});

        var c_name: [*c]u8 = undefined;
        var c_email: [*c]u8 = undefined;

        try internal.wrapCall("git_repository_ident", .{ &c_name, &c_email, internal.toC(self) });

        const name: ?[:0]const u8 = if (c_name) |ptr| std.mem.sliceTo(ptr, 0) else null;
        const email: ?[:0]const u8 = if (c_email) |ptr| std.mem.sliceTo(ptr, 0) else null;

        log.debug("identity acquired: name={s}, email={s}", .{ name, email });

        return Identity{ .name = name, .email = email };
    }

    /// Set the identity to be used for writing reflogs
    ///
    /// If both are set, this name and email will be used to write to the reflog.
    /// Set to `null` to unset; When unset, the identity will be taken from the repository's configuration.
    pub fn identitySet(self: *const Repository, identity: Identity) !void {
        log.debug("Repository.identitySet called, identity.name={s}, identity.email={s}", .{ identity.name, identity.email });

        const name_temp: [*c]const u8 = if (identity.name) |slice| slice.ptr else null;
        const email_temp: [*c]const u8 = if (identity.email) |slice| slice.ptr else null;
        try internal.wrapCall("git_repository_set_ident", .{ internal.toC(self), name_temp, email_temp });

        log.debug("successfully set identity", .{});
    }

    pub const Identity = struct {
        name: ?[:0]const u8,
        email: ?[:0]const u8,
    };

    pub fn namespaceGet(self: *const Repository) !?[:0]const u8 {
        log.debug("Repository.namespaceGet called", .{});

        const ret = raw.git_repository_get_namespace(internal.toC(self));

        if (ret) |ptr| {
            const slice = std.mem.sliceTo(ptr, 0);
            log.debug("namespace: {s}", .{slice});
            return slice;
        }

        log.debug("no namespace", .{});

        return null;
    }

    /// Sets the active namespace for this Git Repository
    ///
    /// This namespace affects all reference operations for the repo. See `man gitnamespaces`
    ///
    /// ## Parameters
    /// * `namespace` - The namespace. This should not include the refs folder, e.g. to namespace all references under 
    ///                 "refs/namespaces/foo/", use "foo" as the namespace.
    pub fn namespaceSet(self: *Repository, namespace: [:0]const u8) !void {
        log.debug("Repository.namespaceSet called, namespace={s}", .{namespace});

        try internal.wrapCall("git_repository_set_namespace", .{ internal.toC(self), namespace.ptr });

        log.debug("successfully set namespace", .{});
    }

    pub fn isHeadDetached(self: *const Repository) !bool {
        log.debug("Repository.isHeadDetached called", .{});

        const ret = (try internal.wrapCallWithReturn("git_repository_head_detached", .{internal.toC(self)})) == 1;

        log.debug("is head detached: {}", .{ret});

        return ret;
    }

    pub fn head(self: *const Repository) !*git.Reference {
        log.debug("Repository.head called", .{});

        var ref: ?*raw.git_reference = undefined;

        try internal.wrapCall("git_repository_head", .{ &ref, internal.toC(self) });

        log.debug("reference opened successfully", .{});

        return internal.fromC(ref.?);
    }

    /// Make the repository HEAD point to the specified reference.
    ///
    /// If the provided reference points to a Tree or a Blob, the HEAD is unaltered and an error is returned.
    ///
    /// If the provided reference points to a branch, the HEAD will point to that branch, staying attached, or become attached if
    /// it isn't yet. If the branch doesn't exist yet, the HEAD will be attached to an unborn branch.
    ///
    /// Otherwise, the HEAD will be detached and will directly point to the commit.
    ///
    /// ## Parameters
    /// * `ref_name` - Canonical name of the reference the HEAD should point at
    pub fn headSet(self: *Repository, ref_name: [:0]const u8) !void {
        log.debug("Repository.headSet called, workdir={s}", .{ref_name});

        try internal.wrapCall("git_repository_set_head", .{ internal.toC(self), ref_name.ptr });

        log.debug("successfully set head", .{});
    }

    /// Make the repository HEAD directly point to a commit.
    ///
    /// If the provided commit cannot be found in the repository `GitError.NotFound` is returned.
    /// If the provided commit cannot be peeled into a commit, the HEAD is unaltered and an error is returned.
    /// Otherwise, the HEAD will eventually be detached and will directly point to the peeled commit.
    ///
    /// ## Parameters
    /// * `commit` - Object id of the commit the HEAD should point to
    pub fn headDetachedSet(self: *Repository, commit: git.Oid) !void {
        // This check is to prevent formating the oid when we are not going to print anything
        if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
            var buf: [git.Oid.HEX_BUFFER_SIZE]u8 = undefined;
            const slice = try commit.formatHex(&buf);
            log.debug("Repository.headDetachedSet called, commit={s}", .{slice});
        }

        try internal.wrapCall("git_repository_set_head_detached", .{ internal.toC(self), internal.toC(&commit) });

        log.debug("successfully set head", .{});
    }

    /// Make the repository HEAD directly point to the commit.
    ///
    /// This behaves like `Repository.setHeadDetached` but takes an annotated commit, which lets you specify which 
    /// extended sha syntax string was specified by a user, allowing for more exact reflog messages.
    ///
    /// See the documentation for `Repository.setHeadDetached`.
    pub fn setHeadDetachedFromAnnotated(self: *Repository, commitish: *const git.AnnotatedCommit) !void {
        // This check is to prevent formating the oid when we are not going to print anything
        if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
            var buf: [git.Oid.HEX_BUFFER_SIZE]u8 = undefined;
            const oid = try commitish.commitId();
            const slice = try oid.formatHex(&buf);
            log.debug("Repository.setHeadDetachedFromAnnotated called, commitish={s}", .{slice});
        }

        try internal.wrapCall("git_repository_set_head_detached_from_annotated", .{ internal.toC(self), internal.toC(commitish) });

        log.debug("successfully set head", .{});
    }

    /// Detach the HEAD.
    ///
    /// If the HEAD is already detached and points to a Tag, the HEAD is updated into making it point to the peeled commit.
    /// If the HEAD is already detached and points to a non commitish, the HEAD is unaltered, and an error is returned.
    ///
    /// Otherwise, the HEAD will be detached and point to the peeled commit.
    pub fn detachHead(self: *Repository) !void {
        log.debug("Repository.detachHead called", .{});

        try internal.wrapCall("git_repository_detach_head", .{internal.toC(self)});

        log.debug("successfully detached the head", .{});
    }

    pub fn isHeadForWorktreeDetached(self: *const Repository, name: [:0]const u8) !bool {
        log.debug("Repository.isHeadForWorktreeDetached called, name={s}", .{name});

        const ret = (try internal.wrapCallWithReturn(
            "git_repository_head_detached_for_worktree",
            .{ internal.toC(self), name.ptr },
        )) == 1;

        log.debug("head for worktree {s} is detached: {}", .{ name, ret });

        return ret;
    }

    pub fn headForWorktree(self: *const Repository, name: [:0]const u8) !*git.Reference {
        log.debug("Repository.headForWorktree called, name={s}", .{name});

        var ref: ?*raw.git_reference = undefined;

        try internal.wrapCall("git_repository_head_for_worktree", .{ &ref, internal.toC(self), name.ptr });

        log.debug("reference opened successfully", .{});

        return internal.fromC(ref.?);
    }

    pub fn isHeadUnborn(self: *const Repository) !bool {
        log.debug("Repository.isHeadUnborn called", .{});

        const ret = (try internal.wrapCallWithReturn("git_repository_head_unborn", .{internal.toC(self)})) == 1;

        log.debug("is head unborn: {}", .{ret});

        return ret;
    }

    pub fn isShallow(self: *const Repository) bool {
        log.debug("Repository.isShallow called", .{});

        const ret = raw.git_repository_is_shallow(internal.toC(self)) == 1;

        log.debug("is repository a shallow clone: {}", .{ret});

        return ret;
    }

    pub fn isEmpty(self: *const Repository) !bool {
        log.debug("Repository.isEmpty called", .{});

        const ret = (try internal.wrapCallWithReturn("git_repository_is_empty", .{internal.toC(self)})) == 1;

        log.debug("is repository empty: {}", .{ret});

        return ret;
    }

    pub fn isBare(self: *const Repository) bool {
        log.debug("Repository.isBare called", .{});

        const ret = raw.git_repository_is_bare(internal.toC(self)) == 1;

        log.debug("is repository bare: {}", .{ret});

        return ret;
    }

    pub fn isWorktree(self: *const Repository) bool {
        log.debug("Repository.isWorktree called", .{});

        const ret = raw.git_repository_is_worktree(internal.toC(self)) == 1;

        log.debug("is repository worktree: {}", .{ret});

        return ret;
    }

    /// Get the location of a specific repository file or directory
    pub fn itemPath(self: *const Repository, item: RepositoryItem) !git.Buf {
        log.debug("Repository.itemPath called, item={s}", .{item});

        var buf = git.Buf{};

        try internal.wrapCall("git_repository_item_path", .{ internal.toC(&buf), internal.toC(self), @enumToInt(item) });

        log.debug("item path: {s}", .{buf.toSlice()});

        return buf;
    }

    pub const RepositoryItem = enum(c_uint) {
        GITDIR,
        WORKDIR,
        COMMONDIR,
        INDEX,
        OBJECTS,
        REFS,
        PACKED_REFS,
        REMOTES,
        CONFIG,
        INFO,
        HOOKS,
        LOGS,
        MODULES,
        WORKTREES,
    };

    pub fn pathGet(self: *const Repository) [:0]const u8 {
        log.debug("Repository.pathGet called", .{});

        const slice = std.mem.sliceTo(raw.git_repository_path(internal.toC(self)), 0);

        log.debug("path: {s}", .{slice});

        return slice;
    }

    pub fn workdirGet(self: *const Repository) ?[:0]const u8 {
        log.debug("Repository.workdirGet called", .{});

        if (raw.git_repository_workdir(internal.toC(self))) |ret| {
            const slice = std.mem.sliceTo(ret, 0);

            log.debug("workdir: {s}", .{slice});

            return slice;
        }

        log.debug("no workdir", .{});

        return null;
    }

    pub fn workdirSet(self: *Repository, workdir: [:0]const u8, update_gitlink: bool) !void {
        log.debug("Repository.workdirSet called, workdir={s}, update_gitlink={}", .{ workdir, update_gitlink });

        try internal.wrapCall("git_repository_set_workdir", .{ internal.toC(self), workdir.ptr, @boolToInt(update_gitlink) });

        log.debug("successfully set workdir", .{});
    }

    pub fn commondir(self: *const Repository) ?[:0]const u8 {
        log.debug("Repository.commondir called", .{});

        if (raw.git_repository_commondir(internal.toC(self))) |ret| {
            const slice = std.mem.sliceTo(ret, 0);

            log.debug("commondir: {s}", .{slice});

            return slice;
        }

        log.debug("no commondir", .{});

        return null;
    }

    /// Get the configuration file for this repository.
    ///
    /// If a configuration file has not been set, the default config set for the repository will be returned, including any global 
    /// and system configurations.
    pub fn configGet(self: *const Repository) !*git.Config {
        log.debug("Repository.configGet called", .{});

        var config: ?*raw.git_config = undefined;

        try internal.wrapCall("git_repository_config", .{ &config, internal.toC(self) });

        log.debug("repository config acquired successfully", .{});

        return internal.fromC(config.?);
    }

    /// Get a snapshot of the repository's configuration
    ///
    /// The contents of this snapshot will not change, even if the underlying config files are modified.
    pub fn configSnapshot(self: *const Repository) !*git.Config {
        log.debug("Repository.configSnapshot called", .{});

        var config: ?*raw.git_config = undefined;

        try internal.wrapCall("git_repository_config_snapshot", .{ &config, internal.toC(self) });

        log.debug("repository config acquired successfully", .{});

        return internal.fromC(config.?);
    }

    pub fn odbGet(self: *const Repository) !*git.Odb {
        log.debug("Repository.odbGet called", .{});

        var odb: ?*raw.git_odb = undefined;

        try internal.wrapCall("git_repository_odb", .{ &odb, internal.toC(self) });

        log.debug("repository odb acquired successfully", .{});

        return internal.fromC(odb.?);
    }

    pub fn refDb(self: *const Repository) !*git.RefDb {
        log.debug("Repository.refDb called", .{});

        var ref_db: ?*raw.git_refdb = undefined;

        try internal.wrapCall("git_repository_refdb", .{ &ref_db, internal.toC(self) });

        log.debug("repository refdb acquired successfully", .{});

        return internal.fromC(ref_db.?);
    }

    pub fn indexGet(self: *const Repository) !*git.Index {
        log.debug("Repository.indexGet called", .{});

        var index: ?*raw.git_index = undefined;

        try internal.wrapCall("git_repository_index", .{ &index, internal.toC(self) });

        log.debug("repository index acquired successfully", .{});

        return internal.fromC(index.?);
    }

    /// Retrieve git's prepared message
    ///
    /// Operations such as git revert/cherry-pick/merge with the -n option stop just short of creating a commit with the changes 
    /// and save their prepared message in .git/MERGE_MSG so the next git-commit execution can present it to the user for them to
    /// amend if they wish.
    ///
    /// Use this function to get the contents of this file. Don't forget to remove the file after you create the commit.
    pub fn preparedMessage(self: *const Repository) !git.Buf {
        log.debug("Repository.preparedMessage called", .{});

        var buf = git.Buf{};

        try internal.wrapCall("git_repository_message", .{ internal.toC(&buf), internal.toC(self) });

        log.debug("prepared message: {s}", .{buf.toSlice()});

        return buf;
    }

    /// Remove git's prepared message file.
    pub fn preparedMessageRemove(self: *Repository) !void {
        log.debug("Repository.preparedMessageRemove called", .{});

        try internal.wrapCall("git_repository_message_remove", .{internal.toC(self)});

        log.debug("successfully removed prepared message", .{});
    }

    /// Remove all the metadata associated with an ongoing command like merge, revert, cherry-pick, etc.
    /// For example: MERGE_HEAD, MERGE_MSG, etc.
    pub fn stateCleanup(self: *Repository) !void {
        log.debug("Repository.stateCleanup called", .{});

        try internal.wrapCall("git_repository_state_cleanup", .{internal.toC(self)});

        log.debug("successfully cleaned state", .{});
    }

    /// Invoke `callback_fn` for each entry in the given FETCH_HEAD file.
    ///
    /// Return a non-zero value from the callback to stop the loop. This non-zero value is returned by the function.
    ///
    /// ## Parameters
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `ref_name` - The reference name
    /// * `remote_url` - The remote URL
    /// * `oid` - The reference OID
    /// * `is_merge` - Was the reference the result of a merge
    pub fn fetchHeadForeach(
        self: *const Repository,
        comptime callback_fn: fn (
            ref_name: [:0]const u8,
            remote_url: [:0]const u8,
            oid: *const git.Oid,
            is_merge: bool,
        ) c_int,
    ) !c_int {
        const cb = struct {
            pub fn cb(
                ref_name: [:0]const u8,
                remote_url: [:0]const u8,
                oid: *const git.Oid,
                is_merge: bool,
                _: *u8,
            ) c_int {
                return callback_fn(ref_name, remote_url, oid, is_merge);
            }
        }.cb;

        var dummy_data: u8 = undefined;
        return self.fetchHeadForeachWithUserData(&dummy_data, cb);
    }

    /// Invoke `callback_fn` for each entry in the given FETCH_HEAD file.
    ///
    /// Return a non-zero value from the callback to stop the loop. This non-zero value is returned by the function.
    ///
    /// ## Parameters
    /// * `user_data` - pointer to user data to be passed to the callback
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `ref_name` - The reference name
    /// * `remote_url` - The remote URL
    /// * `oid` - The reference OID
    /// * `is_merge` - Was the reference the result of a merge
    /// * `user_data_ptr` - pointer to user data
    pub fn fetchHeadForeachWithUserData(
        self: *const Repository,
        user_data: anytype,
        comptime callback_fn: fn (
            ref_name: [:0]const u8,
            remote_url: [:0]const u8,
            oid: *const git.Oid,
            is_merge: bool,
            user_data_ptr: @TypeOf(user_data),
        ) c_int,
    ) !c_int {
        const UserDataType = @TypeOf(user_data);

        const cb = struct {
            pub fn cb(
                c_ref_name: [*c]const u8,
                c_remote_url: [*c]const u8,
                c_oid: [*c]const raw.git_oid,
                c_is_merge: c_uint,
                payload: ?*c_void,
            ) callconv(.C) c_int {
                return callback_fn(
                    std.mem.sliceTo(c_ref_name, 0),
                    std.mem.sliceTo(c_remote_url, 0),
                    internal.fromC(c_oid.?),
                    c_is_merge == 1,
                    @ptrCast(UserDataType, payload),
                );
            }
        }.cb;

        log.debug("Repository.fetchHeadForeachWithUserData called", .{});

        const ret = try internal.wrapCallWithReturn("git_repository_fetchhead_foreach", .{ internal.toC(self), cb, user_data });

        log.debug("callback returned: {}", .{ret});

        return ret;
    }

    /// If a merge is in progress, invoke 'callback' for each commit ID in the MERGE_HEAD file.
    ///
    /// Return a non-zero value from the callback to stop the loop. This non-zero value is returned by the function.
    ///
    /// ## Parameters
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `oid` - The merge OID
    pub fn mergeHeadForeach(
        self: *const Repository,
        comptime callback_fn: fn (oid: *const git.Oid) c_int,
    ) !c_int {
        const cb = struct {
            pub fn cb(oid: *const git.Oid, _: *u8) c_int {
                return callback_fn(oid);
            }
        }.cb;

        var dummy_data: u8 = undefined;
        return self.mergeHeadForeachWithUserData(&dummy_data, cb);
    }

    /// If a merge is in progress, invoke 'callback' for each commit ID in the MERGE_HEAD file.
    ///
    /// Return a non-zero value from the callback to stop the loop. This non-zero value is returned by the function.
    ///
    /// ## Parameters
    /// * `user_data` - pointer to user data to be passed to the callback
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `oid` - The merge OID
    /// * `user_data_ptr` - pointer to user data
    pub fn mergeHeadForeachWithUserData(
        self: *const Repository,
        user_data: anytype,
        comptime callback_fn: fn (
            oid: *const git.Oid,
            user_data_ptr: @TypeOf(user_data),
        ) c_int,
    ) !c_int {
        const UserDataType = @TypeOf(user_data);

        const cb = struct {
            pub fn cb(c_oid: [*c]const raw.git_oid, payload: ?*c_void) callconv(.C) c_int {
                return callback_fn(internal.fromC(c_oid.?), @ptrCast(UserDataType, payload));
            }
        }.cb;

        log.debug("Repository.mergeHeadForeachWithUserData called", .{});

        const ret = try internal.wrapCallWithReturn("git_repository_mergehead_foreach", .{ internal.toC(self), cb, user_data });

        log.debug("callback returned: {}", .{ret});

        return ret;
    }

    /// Calculate hash of file using repository filtering rules.
    ///
    /// If you simply want to calculate the hash of a file on disk with no filters, you can just use `git.Odb.hashFile`.
    /// However, if you want to hash a file in the repository and you want to apply filtering rules (e.g. crlf filters) before
    /// generating the SHA, then use this function.
    ///
    /// Note: if the repository has `core.safecrlf` set to fail and the filtering triggers that failure, then this function will
    /// return an error and not calculate the hash of the file.
    ///
    /// ## Parameters
    /// * `path` - Path to file on disk whose contents should be hashed. This can be a relative path.
    /// * `object_type` - The object type to hash as (e.g. `ObjectType.BLOB`)
    /// * `as_path` - The path to use to look up filtering rules. If this is `null`, then the `path` parameter will be used
    ///               instead. If this is passed as the empty string, then no filters will be applied when calculating the hash.
    pub fn hashFile(
        self: *const Repository,
        path: [:0]const u8,
        object_type: git.ObjectType,
        as_path: ?[:0]const u8,
    ) !*const git.Oid {
        log.debug("Repository.hashFile called, path={s}, object_type={}, as_path={s}", .{ path, object_type, as_path });

        var oid: ?*raw.git_oid = undefined;

        const as_path_temp: [*c]const u8 = if (as_path) |slice| slice.ptr else null;
        try internal.wrapCall("git_repository_hashfile", .{ oid, internal.toC(self), path.ptr, @enumToInt(object_type), as_path_temp });

        const ret = internal.fromC(oid.?);

        // This check is to prevent formating the oid when we are not going to print anything
        if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
            var buf: [git.Oid.HEX_BUFFER_SIZE]u8 = undefined;
            const slice = try ret.formatHex(&buf);
            log.debug("file hash acquired successfully, hash={s}", .{slice});
        }

        return ret;
    }

    /// Get file status for a single file.
    ///
    /// This tries to get status for the filename that you give. If no files match that name (in either the HEAD, index, or
    /// working directory), this returns `GitError.NotFound`.
    ///
    /// If the name matches multiple files (for example, if the `path` names a directory or if running on a case- insensitive
    /// filesystem and yet the HEAD has two entries that both match the path), then this returns `GitError.Ambiguous`.
    ///
    /// This does not do any sort of rename detection.
    pub fn fileStatus(self: *const Repository, path: [:0]const u8) !git.FileStatus {
        log.debug("Repository.fileStatus called, path={s}", .{path});

        var flags: c_uint = undefined;

        try internal.wrapCall("git_status_file", .{ &flags, internal.toC(self), path.ptr });

        const ret = @bitCast(git.FileStatus, flags);

        log.debug("file status: {}", .{ret});

        return ret;
    }

    /// Gather file statuses and run a callback for each one.
    ///
    /// Return a non-zero value from the callback to stop the loop. This non-zero value is returned by the function.
    ///
    /// ## Parameters
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `path` - The file path
    /// * `status` - The status of the file
    pub fn fileStatusForeach(
        self: *const Repository,
        comptime callback_fn: fn (path: [:0]const u8, status: git.FileStatus) c_int,
    ) !c_int {
        const cb = struct {
            pub fn cb(path: [:0]const u8, status: git.FileStatus, _: *u8) c_int {
                return callback_fn(path, status);
            }
        }.cb;

        var dummy_data: u8 = undefined;
        return self.foreachFileStatusWithUserData(&dummy_data, cb);
    }

    /// Gather file statuses and run a callback for each one.
    ///
    /// Return a non-zero value from the callback to stop the loop. This non-zero value is returned by the function.
    ///
    /// ## Parameters
    /// * `user_data` - pointer to user data to be passed to the callback
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `path` - The file path
    /// * `status` - The status of the file
    /// * `user_data_ptr` - pointer to user data
    pub fn fileStatusForeachWithUserData(
        self: *const Repository,
        user_data: anytype,
        comptime callback_fn: fn (
            path: [:0]const u8,
            status: git.FileStatus,
            user_data_ptr: @TypeOf(user_data),
        ) c_int,
    ) !c_int {
        const UserDataType = @TypeOf(user_data);

        const cb = struct {
            pub fn cb(path: [*c]const u8, status: c_uint, payload: ?*c_void) callconv(.C) c_int {
                return callback_fn(
                    std.mem.sliceTo(path, 0),
                    @bitCast(git.FileStatus, status),
                    @intToPtr(UserDataType, @ptrToInt(payload)),
                );
            }
        }.cb;

        log.debug("Repository.fileStatusForeachWithUserData called", .{});

        const ret = try internal.wrapCallWithReturn("git_status_foreach", .{ internal.toC(self), cb, user_data });

        log.debug("callback returned: {}", .{ret});

        return ret;
    }

    /// Gather file status information and run callbacks as requested.
    ///
    /// This is an extended version of the `foreachFileStatus` function that allows for more granular control over which paths
    /// will be processed. See `FileStatusOptions` for details about the additional options that this makes available.
    ///
    /// Note that if a `pathspec` is given in the `FileStatusOptions` to filter the status, then the results from rename
    /// detection (if you enable it) may not be accurate. To do rename detection properly, this must be called with no `pathspec`
    /// so that all files can be considered.
    ///
    /// Return a non-zero value from the callback to stop the loop. This non-zero value is returned by the function.
    ///
    /// ## Parameters
    /// * `options` - callback options
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `path` - The file path
    /// * `status` - The status of the file
    pub fn fileStatusForeachExtended(
        self: *const Repository,
        options: FileStatusOptions,
        comptime callback_fn: fn (path: [:0]const u8, status: git.FileStatus) c_int,
    ) !c_int {
        const cb = struct {
            pub fn cb(path: [:0]const u8, status: git.FileStatus, _: *u8) c_int {
                return callback_fn(path, status);
            }
        }.cb;

        var dummy_data: u8 = undefined;
        return self.foreachFileStatusExtendedWithUserData(options, &dummy_data, cb);
    }

    /// Gather file status information and run callbacks as requested.
    ///
    /// This is an extended version of the `foreachFileStatus` function that allows for more granular control over which paths
    /// will be processed. See `FileStatusOptions` for details about the additional options that this makes available.
    ///
    /// Note that if a `pathspec` is given in the `FileStatusOptions` to filter the status, then the results from rename
    /// detection (if you enable it) may not be accurate. To do rename detection properly, this must be called with no `pathspec`
    /// so that all files can be considered.
    ///
    /// Return a non-zero value from the callback to stop the loop. This non-zero value is returned by the function.
    ///
    /// ## Parameters
    /// * `options` - callback options
    /// * `user_data` - pointer to user data to be passed to the callback
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `path` - The file path
    /// * `status` - The status of the file
    /// * `user_data_ptr` - pointer to user data
    pub fn fileStatusForeachExtendedWithUserData(
        self: *const Repository,
        options: FileStatusOptions,
        user_data: anytype,
        comptime callback_fn: fn (
            path: [:0]const u8,
            status: git.FileStatus,
            user_data_ptr: @TypeOf(user_data),
        ) c_int,
    ) !c_int {
        const UserDataType = @TypeOf(user_data);

        const cb = struct {
            pub fn cb(path: [*c]const u8, status: c_uint, payload: ?*c_void) callconv(.C) c_int {
                return callback_fn(
                    std.mem.sliceTo(path, 0),
                    @bitCast(git.FileStatus, status),
                    @intToPtr(UserDataType, @ptrToInt(payload)),
                );
            }
        }.cb;

        log.debug("Repository.fileStatusForeachExtendedWithUserData called, options={}", .{options});

        var opts: raw.git_status_options = .{
            .version = raw.GIT_REPOSITORY_INIT_OPTIONS_VERSION,
            .show = @enumToInt(options.show),
            .flags = @bitCast(c_int, options.flags),
            .pathspec = internal.toC(options.pathspec),
            .baseline = if (options.baseline) |tree| internal.toC(tree) else null,
        };

        const ret = try internal.wrapCallWithReturn("git_status_foreach_ext", .{ internal.toC(self), &opts, cb, user_data });

        log.debug("callback returned: {}", .{ret});

        return ret;
    }

    /// Gather file status information and populate a `git.StatusList`.
    ///
    /// Note that if a `pathspec` is given in the `FileStatusOptions` to filter the status, then the results from rename detection
    /// (if you enable it) may not be accurate. To do rename detection properly, this must be called with no `pathspec` so that
    /// all files can be considered.
    ///
    /// ## Parameters
    /// * `options` - options regarding which files to get the status of
    pub fn statusList(self: *const Repository, options: FileStatusOptions) !*git.StatusList {
        log.debug("Repository.statusList called, options={}", .{options});

        var opts: raw.git_status_options = .{
            .version = raw.GIT_REPOSITORY_INIT_OPTIONS_VERSION,
            .show = @enumToInt(options.show),
            .flags = @bitCast(c_int, options.flags),
            .pathspec = internal.toC(options.pathspec),
            .baseline = if (options.baseline) |tree| internal.toC(tree) else null,
        };

        var status_list: ?*raw.git_status_list = undefined;
        try internal.wrapCall("git_status_list_new", .{ &status_list, internal.toC(self), &opts });

        log.debug("successfully fetched status list", .{});

        return internal.fromC(status_list.?);
    }

    pub const FileStatusOptions = struct {
        /// which files to scan
        show: Show = .INDEX_AND_WORKDIR,

        /// Flags to control status callbacks
        flags: Flags = .{},

        /// The `pathspec` is an array of path patterns to match (using fnmatch-style matching), or just an array of paths to 
        /// match exactly if `Flags.DISABLE_PATHSPEC_MATCH` is specified in the flags.
        pathspec: git.StrArray = .{},

        /// The `baseline` is the tree to be used for comparison to the working directory and index; defaults to HEAD.
        baseline: ?*const git.Tree = null,

        /// Select the files on which to report status.
        pub const Show = enum(c_uint) {
            /// The default. This roughly matches `git status --porcelain` regarding which files are included and in what order.
            INDEX_AND_WORKDIR,
            /// Only gives status based on HEAD to index comparison, not looking at working directory changes.
            INDEX_ONLY,
            /// Only gives status based on index to working directory comparison, not comparing the index to the HEAD.
            WORKDIR_ONLY,
        };

        /// Flags to control status callbacks
        ///
        /// Calling `Repository.forEachFileStatus` is like calling the extended version with: `INCLUDE_IGNORED`, 
        /// `INCLUDE_UNTRACKED`, and `RECURSE_UNTRACKED_DIRS`. Those options are provided as `Options.DEFAULTS`.
        pub const Flags = packed struct {
            /// Says that callbacks should be made on untracked files.
            /// These will only be made if the workdir files are included in the status
            /// "show" option.
            INCLUDE_UNTRACKED: bool = false,

            /// Says that ignored files get callbacks.
            /// Again, these callbacks will only be made if the workdir files are
            /// included in the status "show" option.
            INCLUDE_IGNORED: bool = false,

            /// Indicates that callback should be made even on unmodified files.
            INCLUDE_UNMODIFIED: bool = false,

            /// Indicates that submodules should be skipped.
            /// This only applies if there are no pending typechanges to the submodule
            /// (either from or to another type).
            EXCLUDE_SUBMODULES: bool = false,

            /// Indicates that all files in untracked directories should be included.
            /// Normally if an entire directory is new, then just the top-level
            /// directory is included (with a trailing slash on the entry name).
            /// This flag says to include all of the individual files in the directory
            /// instead.
            RECURSE_UNTRACKED_DIRS: bool = false,

            /// Indicates that the given path should be treated as a literal path,
            /// and not as a pathspec pattern.
            DISABLE_PATHSPEC_MATCH: bool = false,

            /// Indicates that the contents of ignored directories should be included
            /// in the status. This is like doing `git ls-files -o -i --exclude-standard`
            /// with core git.
            RECURSE_IGNORED_DIRS: bool = false,

            /// Indicates that rename detection should be processed between the head and
            /// the index and enables the GIT_STATUS_INDEX_RENAMED as a possible status
            /// flag.
            RENAMES_HEAD_TO_INDEX: bool = false,

            /// Indicates that rename detection should be run between the index and the
            /// working directory and enabled GIT_STATUS_WT_RENAMED as a possible status
            /// flag.
            RENAMES_INDEX_TO_WORKDIR: bool = false,

            /// Overrides the native case sensitivity for the file system and forces
            /// the output to be in case-sensitive order.
            SORT_CASE_SENSITIVELY: bool = false,

            /// Overrides the native case sensitivity for the file system and forces
            /// the output to be in case-insensitive order.
            SORT_CASE_INSENSITIVELY: bool = false,

            /// Iindicates that rename detection should include rewritten files.
            RENAMES_FROM_REWRITES: bool = false,

            /// Bypasses the default status behavior of doing a "soft" index reload
            /// (i.e. reloading the index data if the file on disk has been modified
            /// outside libgit2).
            NO_REFRESH: bool = false,

            /// Tells libgit2 to refresh the stat cache in the index for files that are
            /// unchanged but have out of date stat einformation in the index.
            /// It will result in less work being done on subsequent calls to get status.
            /// This is mutually exclusive with the NO_REFRESH option.
            UPDATE_INDEX: bool = false,

            /// Normally files that cannot be opened or read are ignored as
            /// these are often transient files; this option will return
            /// unreadable files as `GIT_STATUS_WT_UNREADABLE`.
            INCLUDE_UNREADABLE: bool = false,

            /// Unreadable files will be detected and given the status
            /// untracked instead of unreadable.
            INCLUDE_UNREADABLE_AS_UNTRACKED: bool = false,

            z_padding: u16 = 0,

            pub const DEFAULT: Flags = blk: {
                var opt = Flags{};
                opt.INCLUDE_IGNORED = true;
                opt.INCLUDE_UNTRACKED = true;
                opt.RECURSE_UNTRACKED_DIRS = true;
                break :blk opt;
            };

            pub fn format(
                value: Flags,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = fmt;
                return internal.formatWithoutFields(
                    value,
                    options,
                    writer,
                    &.{"z_padding"},
                );
            }

            test {
                try std.testing.expectEqual(@sizeOf(c_uint), @sizeOf(Flags));
                try std.testing.expectEqual(@bitSizeOf(c_uint), @bitSizeOf(Flags));
            }

            comptime {
                std.testing.refAllDecls(@This());
            }
        };

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    /// Test if the ignore rules apply to a given file.
    ///
    /// ## Parameters
    /// * `path` - The file to check ignores for, rooted at the repo's workdir.
    pub fn statusShouldIgnore(self: *const Repository, path: [:0]const u8) !bool {
        log.debug("Repository.statusShouldIgnore called, path={s}", .{path});

        var result: c_int = undefined;
        try internal.wrapCall("git_status_should_ignore", .{ &result, internal.toC(self), path.ptr });

        const ret = result == 1;

        log.debug("status should ignore: {}", .{ret});

        return ret;
    }

    pub fn annotatedCommitCreateFromFetchHead(
        self: *git.Repository,
        branch_name: [:0]const u8,
        remote_url: [:0]const u8,
        id: git.Oid,
    ) !*git.AnnotatedCommit {
        // This check is to prevent formating the oid when we are not going to print anything
        if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
            var buf: [git.Oid.HEX_BUFFER_SIZE]u8 = undefined;
            const slice = try id.formatHex(&buf);
            log.debug(
                "Repository.annotatedCommitCreateFromFetchHead called, branch_name={s}, remote_url={s}, id={s}",
                .{
                    branch_name,
                    remote_url,
                    slice,
                },
            );
        }

        var result: ?*raw.git_annotated_commit = undefined;
        try internal.wrapCall("git_annotated_commit_from_fetchhead", .{
            &result,
            internal.toC(self),
            branch_name.ptr,
            remote_url.ptr,
            internal.toC(&id),
        });

        log.debug("successfully created annotated commit", .{});

        return internal.fromC(result.?);
    }

    pub fn annotatedCommitCreateFromLookup(self: *Repository, id: git.Oid) !*git.AnnotatedCommit {
        // This check is to prevent formating the oid when we are not going to print anything
        if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
            var buf: [git.Oid.HEX_BUFFER_SIZE]u8 = undefined;
            const slice = try id.formatHex(&buf);
            log.debug("Repository.annotatedCommitCreateFromLookup called, id={s}", .{slice});
        }

        var result: ?*raw.git_annotated_commit = undefined;
        try internal.wrapCall("git_annotated_commit_lookup", .{
            &result,
            internal.toC(self),
            internal.toC(&id),
        });

        log.debug("successfully created annotated commit", .{});

        return internal.fromC(result.?);
    }

    pub fn annotatedCommitCreateFromRevisionString(self: *Repository, revspec: [:0]const u8) !*git.AnnotatedCommit {
        log.debug("Repository.annotatedCommitCreateFromRevisionString called, revspec={s}", .{revspec});

        var result: ?*raw.git_annotated_commit = undefined;
        try internal.wrapCall("git_annotated_commit_from_revspec", .{
            &result,
            internal.toC(self),
            revspec.ptr,
        });

        log.debug("successfully created annotated commit", .{});

        return internal.fromC(result.?);
    }

    /// Apply a `Diff` to the given repository, making changes directly in the working directory, the index, or both.
    ///
    /// ## Parameters
    /// * `diff` - the diff to apply
    /// * `location` - the location to apply (workdir, index or both)
    /// * `options` - the options for the apply (or null for defaults)
    pub fn applyDiff(
        self: *Repository,
        diff: *git.Diff,
        location: ApplyLocation,
        comptime options: ?ApplyOptions,
    ) !void {
        log.debug("Repository.applyDiff called, diff={*}, location={}, options={}", .{ diff, location, options });

        const opts = if (options) |user_options| opts_blk: {
            const delta_cb = if (user_options.delta_cb) |delta_cb| blk: {
                break :blk struct {
                    pub fn cb(delta: [*c]raw.git_diff_delta, payload: ?*c_void) callconv(.C) c_int {
                        _ = payload;
                        return delta_cb(internal.toC(delta));
                    }
                }.cb;
            } else null;

            const hunk_cb = if (user_options.hunk_cb) |hunk_cb| blk: {
                break :blk struct {
                    pub fn cb(hunk: [*c]raw.git_diff_hunk, payload: ?*c_void) callconv(.C) c_int {
                        _ = payload;
                        return hunk_cb(internal.toC(hunk));
                    }
                }.cb;
            } else null;

            var opts: raw.git_apply_options = undefined;
            try internal.wrapCall("git_apply_options_init", .{ &opts, raw.GIT_APPLY_OPTIONS_VERSION });

            opts.delta_cb = delta_cb;
            opts.hunk_cb = hunk_cb;
            opts.payload = null;
            opts.flags = @bitCast(c_uint, user_options.flags);

            break :opts_blk opts;
        } else null;

        try internal.wrapCall("git_apply", .{
            internal.toC(self),
            internal.toC(diff),
            internal.toC(location),
            opts,
        });

        log.debug("apply completed", .{});
    }

    /// Apply a `Diff` to the given repository, making changes directly in the working directory, the index, or both.
    ///
    /// ## Parameters
    /// * `diff` - the diff to apply
    /// * `location` - the location to apply (workdir, index or both)
    /// * `user_data` - user data to be passed to callbacks
    /// * `options` - the options for the apply (or null for defaults)
    pub fn applyDiffWithUserData(
        self: *Repository,
        diff: *git.Diff,
        location: ApplyLocation,
        user_data: anytype,
        comptime options: ?ApplyOptionsWithUserData(@TypeOf(user_data)),
    ) !void {
        const UserDataType = @TypeOf(user_data);

        log.debug("Repository.applyDiffWithUserData called, diff={*}, location={}, options={}", .{ diff, location, options });

        const opts = if (options) |user_options| opts_blk: {
            const delta_cb = if (user_options.delta_cb) |delta_cb| blk: {
                break :blk struct {
                    pub fn cb(delta: [*c]raw.git_diff_delta, payload: ?*c_void) callconv(.C) c_int {
                        return delta_cb(
                            internal.toC(delta.?),
                            @intToPtr(UserDataType, @ptrToInt(payload)),
                        );
                    }
                }.cb;
            } else null;

            const hunk_cb = if (user_options.hunk_cb) |hunk_cb| blk: {
                break :blk struct {
                    pub fn cb(hunk: [*c]raw.git_diff_hunk, payload: ?*c_void) callconv(.C) c_int {
                        return hunk_cb(
                            internal.toC(hunk.?),
                            @intToPtr(UserDataType, @ptrToInt(payload)),
                        );
                    }
                }.cb;
            } else null;

            var opts: raw.git_apply_options = undefined;
            try internal.wrapCall("git_apply_options_init", .{ &opts, raw.GIT_APPLY_OPTIONS_VERSION });

            opts.delta_cb = delta_cb;
            opts.hunk_cb = hunk_cb;
            opts.payload = user_data;
            opts.flags = @bitCast(c_uint, user_options.flags);

            break :opts_blk opts;
        } else null;

        try internal.wrapCall("git_apply", .{
            internal.toC(self),
            internal.toC(diff),
            internal.toC(location),
            opts,
        });

        log.debug("apply completed", .{});
    }

    /// Apply a `Diff` to a `Tree`, and return the resulting image as an index.
    ///
    /// ## Parameters
    /// * `diff` - the diff to apply`
    /// * `preimage` - the tree to apply the diff to
    /// * `options` - the options for the apply (or null for defaults)
    pub fn applyDiffToTree(
        self: *Repository,
        diff: *git.Diff,
        preimage: *git.Tree,
        user_data: anytype,
        comptime options: ?ApplyOptionsWithUserData(@TypeOf(user_data)),
    ) !*git.Index {
        log.debug(
            "Repository.applyDiffToTree called, diff={*}, preimage={*}, options={}",
            .{ diff, preimage, options },
        );

        const opts = if (options) |user_options| opts_blk: {
            const delta_cb = if (user_options.delta_cb) |delta_cb| blk: {
                break :blk struct {
                    pub fn cb(delta: [*c]raw.git_diff_delta, payload: ?*c_void) callconv(.C) c_int {
                        _ = payload;
                        return delta_cb(internal.toC(delta.?));
                    }
                }.cb;
            } else null;

            const hunk_cb = if (user_options.hunk_cb) |hunk_cb| blk: {
                break :blk struct {
                    pub fn cb(hunk: [*c]raw.git_diff_hunk, payload: ?*c_void) callconv(.C) c_int {
                        _ = payload;
                        return hunk_cb(internal.toC(hunk.?));
                    }
                }.cb;
            } else null;

            var opts: raw.git_apply_options = undefined;
            try internal.wrapCall("git_apply_options_init", .{ &opts, raw.GIT_APPLY_OPTIONS_VERSION });

            opts.delta_cb = delta_cb;
            opts.hunk_cb = hunk_cb;
            opts.payload = null;
            opts.flags = @bitCast(c_uint, user_options.flags);

            break :opts_blk opts;
        } else null;

        var ret: [*c]raw.git_index = undefined;

        try internal.wrapCall("git_apply_to_tree", .{
            &ret,
            internal.toC(self),
            internal.toC(preimage),
            internal.toC(diff),
            opts,
        });

        const result = internal.fromC(ret.?);

        log.debug("apply completed, index={*}", .{result});

        return result;
    }

    /// Apply a `Diff` to a `Tree`, and return the resulting image as an index.
    ///
    /// ## Parameters
    /// * `diff` - the diff to apply`
    /// * `preimage` - the tree to apply the diff to
    /// * `user_data` - user data to be passed to callbacks
    /// * `options` - the options for the apply (or null for defaults)
    pub fn applyDiffToTreeWithUserData(
        self: *Repository,
        diff: *git.Diff,
        preimage: *git.Tree,
        user_data: anytype,
        comptime options: ?ApplyOptionsWithUserData(@TypeOf(user_data)),
    ) !*git.Index {
        const UserDataType = @TypeOf(user_data);

        log.debug(
            "Repository.applyDiffToTreeWithUserData called, diff={*}, preimage={*}, options={}",
            .{ diff, preimage, options },
        );

        const opts = if (options) |user_options| opts_blk: {
            const delta_cb = if (user_options.delta_cb) |delta_cb| blk: {
                break :blk struct {
                    pub fn cb(delta: [*c]raw.git_diff_delta, payload: ?*c_void) callconv(.C) c_int {
                        return delta_cb(
                            internal.toC(delta.?),
                            @intToPtr(UserDataType, @ptrToInt(payload)),
                        );
                    }
                }.cb;
            } else null;

            const hunk_cb = if (user_options.hunk_cb) |hunk_cb| blk: {
                break :blk struct {
                    pub fn cb(hunk: [*c]raw.git_diff_hunk, payload: ?*c_void) callconv(.C) c_int {
                        return hunk_cb(
                            internal.toC(hunk.?),
                            @intToPtr(UserDataType, @ptrToInt(payload)),
                        );
                    }
                }.cb;
            } else null;

            var opts: raw.git_apply_options = undefined;
            try internal.wrapCall("git_apply_options_init", .{ &opts, raw.GIT_APPLY_OPTIONS_VERSION });

            opts.delta_cb = delta_cb;
            opts.hunk_cb = hunk_cb;
            opts.payload = user_data;
            opts.flags = @bitCast(c_uint, user_options.flags);

            break :opts_blk opts;
        } else null;

        var ret: [*c]raw.git_index = undefined;

        try internal.wrapCall("git_apply_to_tree", .{
            &ret,
            internal.toC(self),
            internal.toC(preimage),
            internal.toC(diff),
            opts,
        });

        const result = internal.fromC(ret.?);

        log.debug("apply completed, index={*}", .{result});

        return result;
    }

    pub const ApplyOptions = struct {
        /// callback that will be made per delta (file)
        ///
        /// When the callback:
        ///   - returns < 0, the apply process will be aborted.
        ///   - returns > 0, the delta will not be applied, but the apply process continues
        ///   - returns 0, the delta is applied, and the apply process continues.
        delta_cb: ?fn (delta: *const git.DiffDelta) c_int = null,

        /// callback that will be made per hunk
        ///
        /// When the callback:
        ///   - returns < 0, the apply process will be aborted.
        ///   - returns > 0, the hunk will not be applied, but the apply process continues
        ///   - returns 0, the hunk is applied, and the apply process continues.
        hunk_cb: ?fn (hunk: *const git.DiffHunk) c_int = null,

        flags: ApplyOptionsFlags = .{},

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    pub fn ApplyOptionsWithUserData(comptime T: type) type {
        return struct {
            /// callback that will be made per delta (file)
            ///
            /// When the callback:
            ///   - returns < 0, the apply process will be aborted.
            ///   - returns > 0, the delta will not be applied, but the apply process continues
            ///   - returns 0, the delta is applied, and the apply process continues.
            delta_cb: ?fn (delta: *const git.DiffDelta, user_data: T) c_int = null,

            /// callback that will be made per hunk
            ///
            /// When the callback:
            ///   - returns < 0, the apply process will be aborted.
            ///   - returns > 0, the hunk will not be applied, but the apply process continues
            ///   - returns 0, the hunk is applied, and the apply process continues.
            hunk_cb: ?fn (hunk: *const git.DiffHunk, user_data: T) c_int = null,

            flags: ApplyOptionsFlags = .{},

            comptime {
                std.testing.refAllDecls(@This());
            }
        };
    }

    pub const ApplyOptionsFlags = packed struct {
        /// Don't actually make changes, just test that the patch applies. This is the equivalent of `git apply --check`.
        CHECK: bool = false,

        z_padding: u31 = 0,

        pub fn format(
            value: ApplyOptionsFlags,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            return internal.formatWithoutFields(
                value,
                options,
                writer,
                &.{"z_padding"},
            );
        }

        test {
            try std.testing.expectEqual(@sizeOf(c_uint), @sizeOf(ApplyOptionsFlags));
            try std.testing.expectEqual(@bitSizeOf(c_uint), @bitSizeOf(ApplyOptionsFlags));
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    pub const ApplyLocation = enum(c_uint) {
        /// Apply the patch to the workdir, leaving the index untouched.
        /// This is the equivalent of `git apply` with no location argument.
        WORKDIR = 0,

        /// Apply the patch to the index, leaving the working directory
        /// untouched.  This is the equivalent of `git apply --cached`.
        INDEX = 1,

        /// Apply the patch to both the working directory and the index.
        /// This is the equivalent of `git apply --index`.
        BOTH = 2,
    };

    /// Look up the value of one git attribute for path.
    ///
    /// ## Parameters
    /// * `flags` - options for fetching attributes
    /// * `path` - The path to check for attributes.  Relative paths are interpreted relative to the repo root. The file does not
    /// have to exist, but if it does not, then it will be treated as a plain file (not a directory).
    /// * `name` - The name of the attribute to look up.
    pub fn attribute(self: *const Repository, flags: AttributeFlags, path: [:0]const u8, name: [:0]const u8) !git.Attribute {
        log.debug("Repository.attribute called, flags={}, path={s}, name={s}", .{ flags, path, name });

        var result: [*c]const u8 = undefined;
        try internal.wrapCall("git_attr_get", .{
            &result,
            internal.toC(self),
            flags.toC(),
            path.ptr,
            name.ptr,
        });

        log.debug("fetched attribute", .{});

        return git.Attribute{
            .z_attr = result,
        };
    }

    /// Look up a list of git attributes for path.
    ///
    /// Use this if you have a known list of attributes that you want to look up in a single call. This is somewhat more efficient
    /// than calling `attributeGet` multiple times.
    ///
    /// ## Parameters
    /// * `output_buffer` - output buffer, *must* be atleast as long as `names`
    /// * `flags` - options for fetching attributes
    /// * `path` - The path to check for attributes.  Relative paths are interpreted relative to the repo root. The file does not
    /// have to exist, but if it does not, then it will be treated as a plain file (not a directory).
    /// * `names` - The names of the attributes to look up.
    pub fn attributeMany(
        self: *const Repository,
        output_buffer: [][*:0]const u8,
        flags: AttributeFlags,
        path: [:0]const u8,
        names: [][*:0]const u8,
    ) ![]const [*:0]const u8 {
        if (output_buffer.len < names.len) return error.BufferTooShort;

        log.debug("Repository.attributeMany called, flags={}, path={s}", .{ flags, path });

        try internal.wrapCall("git_attr_get_many", .{
            @ptrCast([*c][*c]const u8, output_buffer.ptr),
            internal.toC(self),
            flags.toC(),
            path.ptr,
            names.len,
            @ptrCast([*c][*c]const u8, names.ptr),
        });

        log.debug("fetched attributes", .{});

        return output_buffer[0..names.len];
    }

    /// Invoke `callback_fn` for all the git attributes for a path.
    ///
    ///
    /// ## Parameters
    /// * `flags` - options for fetching attributes
    /// * `path` - The path to check for attributes.  Relative paths are interpreted relative to the repo root. The file does not
    /// have to exist, but if it does not, then it will be treated as a plain file (not a directory).
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `name` - The attribute name
    /// * `value` - The attribute value. May be `null` if the attribute is explicitly set to UNSPECIFIED using the '!' sign.
    pub fn attributeForeach(
        self: *const Repository,
        flags: AttributeFlags,
        path: [:0]const u8,
        comptime callback_fn: fn (
            name: [:0]const u8,
            value: ?[:0]const u8,
        ) c_int,
    ) !c_int {
        const cb = struct {
            pub fn cb(
                name: [*c]const u8,
                value: [*c]const u8,
                payload: ?*c_void,
            ) callconv(.C) c_int {
                _ = payload;
                return callback_fn(
                    std.mem.sliceTo(name, 0),
                    if (value) |ptr| std.mem.sliceTo(ptr, 0) else null,
                );
            }
        }.cb;

        log.debug("Repository.attributeForeach called, flags={}, path={s}", .{ flags, path });

        const ret = try internal.wrapCallWithReturn("git_attr_foreach", .{
            internal.toC(self),
            flags.toC(),
            path.ptr,
            cb,
            null,
        });

        log.debug("callback returned: {}", .{ret});

        return ret;
    }

    /// Invoke `callback_fn` for all the git attributes for a path.
    ///
    /// Return a non-zero value from the callback to stop the loop. This non-zero value is returned by the function.
    ///
    /// ## Parameters
    /// * `flags` - options for fetching attributes
    /// * `path` - The path to check for attributes.  Relative paths are interpreted relative to the repo root. The file does not
    /// have to exist, but if it does not, then it will be treated as a plain file (not a directory).
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `name` - The attribute name
    /// * `value` - The attribute value. May be `null` if the attribute is explicitly set to UNSPECIFIED using the '!' sign.
    /// * `user_data_ptr` - pointer to user data
    pub fn attributeForeachWithUserData(
        self: *const Repository,
        flags: AttributeFlags,
        path: [:0]const u8,
        user_data: anytype,
        comptime callback_fn: fn (
            name: [:0]const u8,
            value: ?[:0]const u8,
            user_data_ptr: @TypeOf(user_data),
        ) c_int,
    ) !c_int {
        const UserDataType = @TypeOf(user_data);

        const cb = struct {
            pub fn cb(
                name: [*c]const u8,
                value: [*c]const u8,
                payload: ?*c_void,
            ) callconv(.C) c_int {
                return callback_fn(
                    std.mem.sliceTo(name, 0),
                    if (value) |ptr| std.mem.sliceTo(ptr, 0) else null,
                    @ptrCast(UserDataType, payload),
                );
            }
        }.cb;

        log.debug("Repository.attributeForeachWithUserData called, flags={}, path={s}", .{ flags, path });

        const ret = try internal.wrapCallWithReturn("git_attr_foreach", .{
            internal.toC(self),
            flags.toC(),
            path.ptr,
            cb,
            user_data,
        });

        log.debug("callback returned: {}", .{ret});

        return ret;
    }

    pub const AttributeFlags = struct {
        location: Location = .FILE_THEN_INDEX,

        /// Controls extended attribute behavior
        extended: Extended = .{},

        pub const Location = enum(u32) {
            FILE_THEN_INDEX = 0,
            INDEX_THEN_FILE = 1,
            INDEX_ONLY = 2,
        };

        pub const Extended = packed struct {
            z_padding1: u2 = 0,

            /// Normally, attribute checks include looking in the /etc (or system equivalent) directory for a `gitattributes`
            /// file. Passing this flag will cause attribute checks to ignore that file. Setting the `NO_SYSTEM` flag will cause
            /// attribute checks to ignore that file.
            NO_SYSTEM: bool = false,

            /// Passing the `INCLUDE_HEAD` flag will use attributes from a `.gitattributes` file in the repository
            /// at the HEAD revision.
            INCLUDE_HEAD: bool = false,

            /// Passing the `INCLUDE_COMMIT` flag will use attributes from a `.gitattributes` file in a specific
            /// commit.
            INCLUDE_COMMIT: if (internal.available(.master)) bool else void = if (internal.available(.master)) false else {},

            z_padding2: if (internal.available(.master)) u27 else u28 = 0,

            pub fn format(
                value: Extended,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = fmt;
                return internal.formatWithoutFields(
                    value,
                    options,
                    writer,
                    &.{ "z_padding1", "z_padding2" },
                );
            }

            test {
                try std.testing.expectEqual(@sizeOf(u32), @sizeOf(Extended));
                try std.testing.expectEqual(@bitSizeOf(u32), @bitSizeOf(Extended));
            }

            comptime {
                std.testing.refAllDecls(@This());
            }
        };

        fn toC(self: AttributeFlags) u32 {
            var result: u32 = 0;

            switch (self.location) {
                .FILE_THEN_INDEX => {},
                .INDEX_THEN_FILE => result |= raw.GIT_ATTR_CHECK_INDEX_THEN_FILE,
                .INDEX_ONLY => result |= raw.GIT_ATTR_CHECK_INDEX_ONLY,
            }

            if (self.extended.NO_SYSTEM) {
                result |= raw.GIT_ATTR_CHECK_NO_SYSTEM;
            }

            if (self.extended.INCLUDE_HEAD) {
                result |= raw.GIT_ATTR_CHECK_INCLUDE_HEAD;
            }

            if (comptime internal.available(.master)) {
                if (self.extended.INCLUDE_COMMIT) {
                    result |= raw.GIT_ATTR_CHECK_INCLUDE_COMMIT;
                }
            }

            return result;
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    pub fn attributeCacheFlush(self: *Repository) !void {
        log.debug("Repository.attributeCacheFlush called", .{});

        try internal.wrapCall("git_attr_cache_flush", .{internal.toC(self)});

        log.debug("successfully flushed attribute cache", .{});
    }

    pub fn attributeAddMacro(self: *Repository, name: [:0]const u8, values: [:0]const u8) !void {
        log.debug("Repository.attributeCacheFlush called, name={s}, values={s}", .{ name, values });

        try internal.wrapCall("git_attr_add_macro", .{ internal.toC(self), name.ptr, values.ptr });

        log.debug("successfully added macro", .{});
    }

    pub fn blameFile(self: *const Repository, path: [:0]const u8, options: ?BlameOptions) !*git.Blame {
        log.debug("Repository.blameFile called, path={s}, options={}", .{ path, options });

        var blame: ?*raw.git_blame = undefined;

        if (options) |user_options| {
            var opts: raw.git_blame_options = .{
                .version = raw.GIT_BLAME_OPTIONS_VERSION,
                .flags = @bitCast(u32, user_options.flags),
                .min_match_characters = user_options.min_match_characters,
                .newest_commit = internal.toC(user_options.newest_commit),
                .oldest_commit = internal.toC(user_options.oldest_commit),
                .min_line = user_options.min_line,
                .max_line = user_options.max_line,
            };

            try internal.wrapCall("git_blame_file", .{ &blame, internal.toC(self), path.ptr, &opts });
        } else {
            try internal.wrapCall("git_blame_file", .{ &blame, internal.toC(self), path.ptr, null });
        }

        log.debug("successfully fetched file blame", .{});

        return internal.fromC(blame.?);
    }

    pub const BlameOptions = struct {
        flags: BlameFlags = .{},

        /// The lower bound on the number of alphanumeric characters that must be detected as moving/copying within a file for it
        /// to associate those lines with the parent commit. The default value is 20.
        ///
        /// This value only takes effect if any of the `BlameFlags.TRACK_COPIES_*` flags are specified.
        min_match_characters: u16 = 0,

        /// The id of the newest commit to consider. The default is HEAD.
        newest_commit: git.Oid = git.Oid.zero(),

        /// The id of the oldest commit to consider. The default is the first commit encountered with a NULL parent.
        oldest_commit: git.Oid = git.Oid.zero(),

        /// The first line in the file to blame. The default is 1 (line numbers start with 1).
        min_line: usize = 0,

        /// The last line in the file to blame. The default is the last line of the file.
        max_line: usize = 0,

        pub const BlameFlags = packed struct {
            NORMAL: bool = false,

            /// Track lines that have moved within a file (like `git blame -M`).
            ///
            /// This is not yet implemented and reserved for future use.
            TRACK_COPIES_SAME_FILE: bool = false,

            /// Track lines that have moved across files in the same commit (like `git blame -C`).
            ///
            /// This is not yet implemented and reserved for future use.
            TRACK_COPIES_SAME_COMMIT_MOVES: bool = false,

            /// Track lines that have been copied from another file that exists in the same commit (like `git blame -CC`). 
            /// Implies SAME_FILE.
            ///
            /// This is not yet implemented and reserved for future use.
            TRACK_COPIES_SAME_COMMIT_COPIES: bool = false,

            /// Track lines that have been copied from another file that exists in *any* commit (like `git blame -CCC`). Implies
            /// SAME_COMMIT_COPIES.
            ///
            /// This is not yet implemented and reserved for future use.
            TRACK_COPIES_ANY_COMMIT_COPIES: bool = false,

            /// Restrict the search of commits to those reachable following only the first parents.
            FIRST_PARENT: bool = false,

            /// Use mailmap file to map author and committer names and email addresses to canonical real names and email
            /// addresses. The mailmap will be read from the working directory, or HEAD in a bare repository.
            USE_MAILMAP: bool = false,

            /// Ignore whitespace differences 
            IGNORE_WHITESPACE: bool = false,

            z_padding1: u8 = 0,
            z_padding2: u16 = 0,

            pub fn format(
                value: BlameFlags,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = fmt;
                return internal.formatWithoutFields(
                    value,
                    options,
                    writer,
                    &.{ "z_padding1", "z_padding2" },
                );
            }

            test {
                try std.testing.expectEqual(@sizeOf(u32), @sizeOf(BlameFlags));
                try std.testing.expectEqual(@bitSizeOf(u32), @bitSizeOf(BlameFlags));
            }

            comptime {
                std.testing.refAllDecls(@This());
            }
        };

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    pub fn blobLookup(self: *const Repository, id: *const git.Oid) !*git.Blob {
        // This check is to prevent formating the oid when we are not going to print anything
        if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
            var buf: [git.Oid.HEX_BUFFER_SIZE]u8 = undefined;
            const slice = try id.formatHex(&buf);
            log.debug("Repository.blobLookup called, id={s}", .{slice});
        }

        var blob: ?*raw.git_blob = undefined;

        try internal.wrapCall("git_blob_lookup", .{ &blob, internal.toC(self), internal.toC(id) });

        log.debug("successfully fetched blob {*}", .{blob});

        return internal.fromC(blob.?);
    }

    /// Lookup a blob object from a repository, given a prefix of its identifier (short id).
    pub fn blobLookupPrefix(self: *const Repository, id: *const git.Oid, len: usize) !*git.Blob {
        // This check is to prevent formating the oid when we are not going to print anything
        if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
            var buf: [git.Oid.HEX_BUFFER_SIZE]u8 = undefined;
            const slice = try id.formatHex(&buf);
            log.debug("Repository.blobLookup called, id={s}, len={}", .{ slice, len });
        }

        var blob: ?*raw.git_blob = undefined;

        try internal.wrapCall("git_blob_lookup_prefix", .{ &blob, internal.toC(self), internal.toC(id), len });

        log.debug("successfully fetched blob {*}", .{blob});

        return internal.fromC(blob.?);
    }

    /// Create a new branch pointing at a target commit
    ///
    /// A new direct reference will be created pointing to this target commit. If `force` is true and a reference already exists
    /// with the given name, it'll be replaced.
    ///
    /// The returned reference must be freed by the user.
    ///
    /// The branch name will be checked for validity.
    ///
    /// ## Parameters
    /// * `branch_name` - Name for the branch; this name is validated for consistency. It should also not conflict with an already
    /// existing branch name.
    /// * `target` - Commit to which this branch should point. This object must belong to the given `repo`.
    /// * `force` - Overwrite existing branch.
    pub fn branchCreate(self: *Repository, branch_name: [:0]const u8, target: *const git.Commit, force: bool) !*git.Reference {
        log.debug("Repository.branchCreate called, branch_name={s}, target={*}, force={}", .{ branch_name, target, force });

        var reference: ?*raw.git_reference = undefined;

        try internal.wrapCall("git_branch_create", .{
            &reference,
            internal.toC(self),
            branch_name.ptr,
            internal.toC(target),
            @boolToInt(force),
        });

        log.debug("successfully created branch", .{});

        return internal.fromC(reference.?);
    }

    /// Create a new branch pointing at a target commit
    ///
    /// This behaves like `branchCreate` but takes an annotated commit, which lets you specify which extended sha syntax string
    /// was specified by a user, allowing for more exact reflog messages.
    ///
    /// ## Parameters
    /// * `branch_name` - Name for the branch; this name is validated for consistency. It should also not conflict with an already
    /// existing branch name.
    /// * `target` - Commit to which this branch should point. This object must belong to the given `repo`.
    /// * `force` - Overwrite existing branch.
    pub fn branchCreateFromAnnotated(
        self: *Repository,
        branch_name: [:0]const u8,
        target: *const git.AnnotatedCommit,
        force: bool,
    ) !*git.Reference {
        log.debug("Repository.branchCreateFromAnnotated called, branch_name={s}, target={*}, force={}", .{ branch_name, target, force });

        var reference: ?*raw.git_reference = undefined;

        try internal.wrapCall("git_branch_create_from_annotated", .{
            &reference,
            internal.toC(self),
            branch_name.ptr,
            internal.toC(target),
            @boolToInt(force),
        });

        log.debug("successfully created branch", .{});

        return internal.fromC(reference.?);
    }

    pub fn iterateBranches(self: *const Repository, branch_type: BranchType) !*BranchIterator {
        log.debug("Repository.iterateBranches called", .{});

        var iterator: ?*raw.git_branch_iterator = undefined;

        try internal.wrapCall("git_branch_iterator_new", .{ &iterator, internal.toC(self), @enumToInt(branch_type) });

        log.debug("branch iterator created successfully", .{});

        return internal.fromC(iterator.?);
    }

    pub const BranchType = enum(c_uint) {
        LOCAL = 1,
        REMOTE = 2,
        ALL = 3,
    };

    pub const BranchIterator = opaque {
        pub fn next(self: *BranchIterator) !?Item {
            log.debug("BranchIterator.next called", .{});

            var reference: ?*raw.git_reference = undefined;
            var branch_type: raw.git_branch_t = undefined;

            internal.wrapCall("git_branch_next", .{ &reference, &branch_type, internal.toC(self) }) catch |err| switch (err) {
                git.GitError.IterOver => {
                    log.debug("end of iteration reached", .{});
                    return null;
                },
                else => return err,
            };

            const ret = Item{
                .reference = internal.fromC(reference.?),
                .branch_type = @intToEnum(BranchType, branch_type),
            };

            log.debug("successfully fetched branch: {}", .{ret});

            return ret;
        }

        pub const Item = struct {
            reference: *git.Reference,
            branch_type: BranchType,
        };

        pub fn deinit(self: *BranchIterator) void {
            log.debug("BranchIterator.deinit called", .{});

            raw.git_branch_iterator_free(internal.toC(self));

            log.debug("branch iterator freed successfully", .{});
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    /// Lookup a branch by its name in a repository.
    ///
    /// The generated reference must be freed by the user.
    /// The branch name will be checked for validity.
    pub fn branchLookup(self: *const Repository, branch_name: [:0]const u8, branch_type: BranchType) !*git.Reference {
        log.debug("Repository.branchLookup called, branch_name={s}, branch_type={}", .{ branch_name, branch_type });

        var ref: ?*raw.git_reference = undefined;

        try internal.wrapCall("git_branch_lookup", .{ &ref, internal.toC(self), branch_name.ptr, @enumToInt(branch_type) });

        log.debug("successfully fetched branch: {*}", .{ref});

        return internal.fromC(ref.?);
    }

    /// Find the remote name of a remote-tracking branch
    ///
    /// This will return the name of the remote whose fetch refspec is matching the given branch. E.g. given a branch
    /// "refs/remotes/test/master", it will extract the "test" part. If refspecs from multiple remotes match, the function will
    /// return `GitError.AMBIGUOUS`.
    pub fn remoteGetName(self: *Repository, refname: [:0]const u8) !git.Buf {
        log.debug("Repository.remoteGetName called, refname={s}", .{refname});

        var c_buf: raw.git_buf = undefined;

        try internal.wrapCall("git_branch_remote_name", .{ &c_buf, internal.toC(self), refname.ptr });

        const ret = internal.fromC(c_buf);

        log.debug("remote name acquired successfully, name={s}", .{ret.toSlice()});

        return ret;
    }

    /// Retrieve the upstream remote of a local branch
    ///
    /// This will return the currently configured "branch.*.remote" for a given branch. This branch must be local.
    pub fn remoteUpstreamRemote(self: *Repository, refname: [:0]const u8) !git.Buf {
        log.debug("Repository.remoteUpstreamRemote called, refname={s}", .{refname});

        var c_buf: raw.git_buf = undefined;

        try internal.wrapCall("git_branch_upstream_remote", .{ &c_buf, internal.toC(self), refname.ptr });

        const ret = internal.fromC(c_buf);

        log.debug("upstream remote name acquired successfully, name={s}", .{ret.toSlice()});

        return ret;
    }

    /// Get the upstream name of a branch
    ///
    /// Given a local branch, this will return its remote-tracking branch information, as a full reference name, ie.
    /// "feature/nice" would become "refs/remote/origin/feature/nice", depending on that branch's configuration.
    pub fn upstreamGetName(self: *Repository, refname: [:0]const u8) !git.Buf {
        log.debug("Repository.upstreamGetName called, refname={s}", .{refname});

        var c_buf: raw.git_buf = undefined;

        try internal.wrapCall("git_branch_upstream_name", .{ &c_buf, internal.toC(self), refname.ptr });

        const ret = internal.fromC(c_buf);

        log.debug("upstream name acquired successfully, name={s}", .{ret.toSlice()});

        return ret;
    }

    pub usingnamespace if (internal.available(.master)) struct {
        /// Retrieve the upstream merge of a local branch
        ///
        /// This will return the currently configured "branch.*.remote" for a given branch. This branch must be local.
        pub fn remoteUpstreamMerge(self: *Repository, refname: [:0]const u8) !git.Buf {
            log.debug("Repository.remoteUpstreamMerge called, refname={s}", .{refname});

            var c_buf: raw.git_buf = undefined;

            try internal.wrapCall("git_branch_upstream_merge", .{ &c_buf, internal.toC(self), refname.ptr });

            const ret = internal.fromC(c_buf);

            log.debug("upstream remote name acquired successfully, name={s}", .{ret.toSlice()});

            return ret;
        }

        /// Look up the value of one git attribute for path with extended options.
        ///
        /// ## Parameters
        /// * `options` - options for fetching attributes
        /// * `path` - The path to check for attributes.  Relative paths are interpreted relative to the repo root. The file does not
        /// have to exist, but if it does not, then it will be treated as a plain file (not a directory).
        /// * `name` - The name of the attribute to look up.
        pub fn attributeExtended(
            self: *const Repository,
            options: AttributeOptions,
            path: [:0]const u8,
            name: [:0]const u8,
        ) !git.Attribute {
            log.debug("Repository.attributeExtended called, options={}, path={s}, name={s}", .{ options, path, name });

            var opts: raw.git_attr_options = .{
                .version = raw.GIT_ATTR_OPTIONS_VERSION,
                .flags = options.flags.toC(),
                .commit_id = internal.toC(options.commit_id),
            };

            var result: [*c]const u8 = undefined;
            try internal.wrapCall("git_attr_get_ext", .{
                &result,
                internal.toC(self),
                &opts,
                path.ptr,
                name.ptr,
            });

            log.debug("fetched attribute", .{});

            return git.Attribute{
                .z_attr = result,
            };
        }

        /// Look up a list of git attributes for path with extended options.
        ///
        /// Use this if you have a known list of attributes that you want to look up in a single call. This is somewhat more efficient
        /// than calling `attributeGet` multiple times.
        ///
        /// ## Parameters
        /// * `output_buffer` - output buffer, *must* be atleast as long as `names`
        /// * `options` - options for fetching attributes
        /// * `path` - The path to check for attributes.  Relative paths are interpreted relative to the repo root. The file does not
        /// have to exist, but if it does not, then it will be treated as a plain file (not a directory).
        /// * `names` - The names of the attributes to look up.
        pub fn attributeManyExtended(
            self: *const Repository,
            output_buffer: [][*:0]const u8,
            options: AttributeOptions,
            path: [:0]const u8,
            names: [][*:0]const u8,
        ) ![]const [*:0]const u8 {
            if (output_buffer.len < names.len) return error.BufferTooShort;

            log.debug("Repository.attributeManyExtended called, options={}, path={s}", .{ options, path });

            var opts: raw.git_attr_options = .{
                .version = raw.GIT_ATTR_OPTIONS_VERSION,
                .flags = options.flags.toC(),
                .commit_id = internal.toC(options.commit_id),
            };

            try internal.wrapCall("git_attr_get_many_ext", .{
                @ptrCast([*c][*c]const u8, output_buffer.ptr),
                internal.toC(self),
                &opts,
                path.ptr,
                names.len,
                @ptrCast([*c][*c]const u8, names.ptr),
            });

            log.debug("fetched attributes", .{});

            return output_buffer[0..names.len];
        }

        /// Invoke `callback_fn` for all the git attributes for a path with extended options.
        ///
        ///
        /// ## Parameters
        /// * `options` - options for fetching attributes
        /// * `path` - The path to check for attributes.  Relative paths are interpreted relative to the repo root. The file does not
        /// have to exist, but if it does not, then it will be treated as a plain file (not a directory).
        /// * `callback_fn` - the callback function
        ///
        /// ## Callback Parameters
        /// * `name` - The attribute name
        /// * `value` - The attribute value. May be `null` if the attribute is explicitly set to UNSPECIFIED using the '!' sign.
        pub fn attributeForeachExtended(
            self: *const Repository,
            options: AttributeOptions,
            path: [:0]const u8,
            comptime callback_fn: fn (
                name: [:0]const u8,
                value: ?[:0]const u8,
            ) c_int,
        ) !c_int {
            const cb = struct {
                pub fn cb(
                    name: [*c]const u8,
                    value: [*c]const u8,
                    payload: ?*c_void,
                ) callconv(.C) c_int {
                    _ = payload;
                    return callback_fn(
                        std.mem.sliceTo(name, 0),
                        if (value) |ptr| std.mem.sliceTo(ptr, 0) else null,
                    );
                }
            }.cb;

            log.debug("Repository.attributeForeach called, options={}, path={s}", .{ options, path });

            var opts: raw.git_attr_options = .{
                .version = raw.GIT_ATTR_OPTIONS_VERSION,
                .flags = options.flags.toC(),
                .commit_id = internal.toC(options.commit_id),
            };

            const ret = try internal.wrapCallWithReturn("git_attr_foreach_ext", .{
                internal.toC(self),
                &opts,
                path.ptr,
                cb,
                null,
            });

            log.debug("callback returned: {}", .{ret});

            return ret;
        }

        /// Invoke `callback_fn` for all the git attributes for a path with extended options.
        ///
        /// Return a non-zero value from the callback to stop the loop. This non-zero value is returned by the function.
        ///
        /// ## Parameters
        /// * `options` - options for fetching attributes
        /// * `path` - The path to check for attributes.  Relative paths are interpreted relative to the repo root. The file does not
        /// have to exist, but if it does not, then it will be treated as a plain file (not a directory).
        /// * `callback_fn` - the callback function
        ///
        /// ## Callback Parameters
        /// * `name` - The attribute name
        /// * `value` - The attribute value. May be `null` if the attribute is explicitly set to UNSPECIFIED using the '!' sign.
        /// * `user_data_ptr` - pointer to user data
        pub fn attributeForeachWithUserDataExtended(
            self: *const Repository,
            options: AttributeOptions,
            path: [:0]const u8,
            user_data: anytype,
            comptime callback_fn: fn (
                name: [:0]const u8,
                value: ?[:0]const u8,
                user_data_ptr: @TypeOf(user_data),
            ) c_int,
        ) !c_int {
            const UserDataType = @TypeOf(user_data);

            const cb = struct {
                pub fn cb(
                    name: [*c]const u8,
                    value: [*c]const u8,
                    payload: ?*c_void,
                ) callconv(.C) c_int {
                    return callback_fn(
                        std.mem.sliceTo(name, 0),
                        if (value) |ptr| std.mem.sliceTo(ptr, 0) else null,
                        @ptrCast(UserDataType, payload),
                    );
                }
            }.cb;

            log.debug("Repository.attributeForeachWithUserData called, options={}, path={s}", .{ options, path });

            var opts: raw.git_attr_options = .{
                .version = raw.GIT_ATTR_OPTIONS_VERSION,
                .flags = options.flags.toC(),
                .commit_id = internal.toC(options.commit_id),
            };

            const ret = try internal.wrapCallWithReturn("git_attr_foreach_ext", .{
                internal.toC(self),
                &opts,
                path.ptr,
                cb,
                user_data,
            });

            log.debug("callback returned: {}", .{ret});

            return ret;
        }

        pub const AttributeOptions = struct {
            flags: AttributeFlags,
            commit_id: *git.Oid,

            comptime {
                std.testing.refAllDecls(@This());
            }
        };
    } else struct {};

    pub usingnamespace if (internal.available(.@"0.99.0")) struct {
        /// Read a file from the filesystem and write its content to the Object Database as a loose blob
        pub fn blobFromBuffer(self: *Repository, buffer: []const u8) !git.Oid {
            log.debug("Repository.blobFromBuffer called, buffer={s}", .{buffer});

            var oid: raw.git_oid = undefined;

            try internal.wrapCall("git_blob_create_from_buffer", .{ &oid, internal.toC(self), buffer.ptr, buffer.len });

            const ret = internal.fromC(oid);

            // This check is to prevent formating the oid when we are not going to print anything
            if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
                var buf: [git.Oid.HEX_BUFFER_SIZE]u8 = undefined;
                const slice = try ret.formatHex(&buf);
                log.debug("successfully read blob: {s}", .{slice});
            }

            return ret;
        }

        /// Create a stream to write a new blob into the object db
        ///
        /// This function may need to buffer the data on disk and will in general not be the right choice if you know the size of the
        /// data to write. If you have data in memory, use `blobFromBuffer()`. If you do not, but know the size of the contents
        /// (and don't want/need to perform filtering), use `Odb.openWriteStream()`.
        ///
        /// Don't close this stream yourself but pass it to `WriteStream.commit()` to commit the write to the object db and get the
        /// object id.
        ///
        /// If the `hintpath` parameter is filled, it will be used to determine what git filters should be applied to the object
        /// before it is written to the object database.
        pub fn blobFromStream(self: *Repository, hint_path: ?[:0]const u8) !*git.WriteStream {
            log.debug("Repository.blobFromDisk called, hint_path={s}", .{hint_path});

            var write_stream: [*c]raw.git_writestream = undefined;

            const hint_path_c = if (hint_path) |ptr| ptr.ptr else null;
            try internal.wrapCall("git_blob_create_from_stream", .{ &write_stream, internal.toC(self), hint_path_c });

            const ret = internal.fromC(write_stream);

            log.debug("successfully created writestream {*}", .{write_stream});

            return ret;
        }

        /// Read a file from the filesystem and write its content to the Object Database as a loose blob
        pub fn blobFromDisk(self: *Repository, path: [:0]const u8) !git.Oid {
            log.debug("Repository.blobFromDisk called, path={s}", .{path});

            var oid: raw.git_oid = undefined;

            try internal.wrapCall("git_blob_create_from_disk", .{ &oid, internal.toC(self), path.ptr });

            const ret = internal.fromC(oid);

            // This check is to prevent formating the oid when we are not going to print anything
            if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
                var buf: [git.Oid.HEX_BUFFER_SIZE]u8 = undefined;
                const slice = try ret.formatHex(&buf);
                log.debug("successfully read blob: {s}", .{slice});
            }

            return ret;
        }

        /// Read a file from the working folder of a repository and write it to the Object Database as a loose blob
        pub fn blobFromWorkdir(self: *Repository, relative_path: [:0]const u8) !git.Oid {
            log.debug("Repository.blobFromWorkdir called, relative_path={s}", .{relative_path});

            var oid: raw.git_oid = undefined;

            try internal.wrapCall("git_blob_create_from_workdir", .{ &oid, internal.toC(self), relative_path.ptr });

            const ret = internal.fromC(oid);

            // This check is to prevent formating the oid when we are not going to print anything
            if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
                var buf: [git.Oid.HEX_BUFFER_SIZE]u8 = undefined;
                const slice = try ret.formatHex(&buf);
                log.debug("successfully read blob: {s}", .{slice});
            }

            return ret;
        }
    } else struct {};

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
