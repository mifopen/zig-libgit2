const std = @import("std");
const raw = @import("raw.zig");

const log = std.log.scoped(.git);

/// Only one instance of `Handle` should be initalized at any one time
pub fn init() !Handle {
    log.debug("init called", .{});

    checkUninitialized();

    try wrapCall("git_libgit2_init", .{});

    if (std.builtin.mode == .Debug) {
        initialized = true;
    }

    log.info("libgit initalization successful", .{});

    return Handle{};
}

/// Only one instance of `Handle` should be initalized at any one time
pub const Handle = struct {
    pub fn deinit(self: Handle) void {
        _ = self;

        log.debug("Handle.deinit called", .{});

        checkInitialized();

        wrapCall("git_libgit2_shutdown", .{}) catch unreachable;

        if (std.builtin.mode == .Debug) {
            initialized = false;
        }

        log.debug("libgit shutdown successfully", .{});
    }

    pub fn openRepository(self: Handle, path: [:0]const u8) !GitRepository {
        _ = self;

        log.debug("Handle.openRepository called, path={s}", .{path});

        var repo: ?*raw.git_repository = undefined;

        try wrapCall("git_repository_open", .{ &repo, path.ptr });

        log.debug("repository opened successfully", .{});

        return GitRepository{ .repo = repo.? };
    }
};

pub const GitRepository = struct {
    repo: *raw.git_repository = undefined,

    pub fn deinit(self: *GitRepository) void {
        log.debug("GitRepository.deinit called", .{});

        raw.git_repository_free(self.repo);
        self.* = undefined;

        log.debug("repository closed successfully", .{});
    }
};

pub const GitError = error{
    /// Generic error
    GenericError,
    /// Requested object could not be found
    NotFound,
    /// Object exists preventing operation
    Exists,
    /// More than one object matches
    Ambiguous,
    /// Output buffer too short to hold data
    BufferTooShort,
    /// A special error that is never generated by libgit2
    /// code.  You can return it from a callback (e.g to stop an iteration)
    /// to know that it was generated by the callback and not by libgit2.
    User,
    /// Operation not allowed on bare repository
    BareRepo,
    /// HEAD refers to branch with no commits
    UnbornBranch,
    /// Merge in progress prevented operation
    Unmerged,
    /// Reference was not fast-forwardable
    NonFastForwardable,
    /// Name/ref spec was not in a valid format
    InvalidSpec,
    /// Checkout conflicts prevented operation
    Conflict,
    /// Lock file prevented operation
    Locked,
    /// Reference value does not match expected
    Modifed,
    /// Authentication error
    Auth,
    /// Server certificate is invalid
    Certificate,
    /// Patch/merge has already been applied
    Applied,
    /// The requested peel operation is not possible
    Peel,
    /// Unexpected EOF
    EndOfFile,
    /// Invalid operation or input
    Invalid,
    /// Uncommitted changes in index prevented operation
    Uncommited,
    /// The operation is not valid for a directory
    Directory,
    /// A merge conflict exists and cannot continue
    MergeConflict,
    /// A user-configured callback refused to act
    Passthrough,
    /// Signals end of iteration with iterator
    IterOver,
    /// Internal only
    Retry,
    /// Hashsum mismatch in object
    Mismatch,
    /// Unsaved changes in the index would be overwritten
    IndexDirty,
    /// Patch application failed
    ApplyFail,
};

inline fn wrapCall(comptime name: []const u8, args: anytype) GitError!void {
    checkForError(@call(.{}, @field(raw, name), args)) catch |err| {
        log.emerg(name ++ " failed with error {}", .{err});
        return err;
    };
}

inline fn wrapCallWithReturn(
    comptime name: []const u8,
    args: anytype,
) GitError!(@typeInfo(@TypeOf(@field(raw, name))).Fn.return_type orelse void) {
    const value = @call(.{}, @field(raw, name), args);
    checkForError(value) catch |err| {
        log.emerg(name ++ " failed with error {}", .{err});
        return err;
    };
    return value;
}

fn checkForError(value: raw.git_error_code) GitError!void {
    if (value >= 0) return;
    return switch (value) {
        raw.GIT_ERROR => GitError.GenericError,
        raw.GIT_ENOTFOUND => GitError.NotFound,
        raw.GIT_EEXISTS => GitError.Exists,
        raw.GIT_EAMBIGUOUS => GitError.Ambiguous,
        raw.GIT_EBUFS => GitError.BufferTooShort,
        raw.GIT_EUSER => GitError.User,
        raw.GIT_EBAREREPO => GitError.BareRepo,
        raw.GIT_EUNBORNBRANCH => GitError.UnbornBranch,
        raw.GIT_EUNMERGED => GitError.Unmerged,
        raw.GIT_ENONFASTFORWARD => GitError.NonFastForwardable,
        raw.GIT_EINVALIDSPEC => GitError.InvalidSpec,
        raw.GIT_ECONFLICT => GitError.Conflict,
        raw.GIT_ELOCKED => GitError.Locked,
        raw.GIT_EMODIFIED => GitError.Modifed,
        raw.GIT_EAUTH => GitError.Auth,
        raw.GIT_ECERTIFICATE => GitError.Certificate,
        raw.GIT_EAPPLIED => GitError.Applied,
        raw.GIT_EPEEL => GitError.Peel,
        raw.GIT_EEOF => GitError.EndOfFile,
        raw.GIT_EINVALID => GitError.Invalid,
        raw.GIT_EUNCOMMITTED => GitError.Uncommited,
        raw.GIT_EDIRECTORY => GitError.Directory,
        raw.GIT_EMERGECONFLICT => GitError.MergeConflict,
        raw.GIT_PASSTHROUGH => GitError.Passthrough,
        raw.GIT_ITEROVER => GitError.IterOver,
        raw.GIT_RETRY => GitError.Retry,
        raw.GIT_EMISMATCH => GitError.Mismatch,
        raw.GIT_EINDEXDIRTY => GitError.IndexDirty,
        raw.GIT_EAPPLYFAIL => GitError.ApplyFail,
        else => {
            log.emerg("encountered unknown libgit2 error: {}", .{value});
            unreachable;
        },
    };
}

// TODO: Should the code that checks/sets `initialized` be atomic?
usingnamespace if (std.builtin.mode == .Debug) struct {
    pub var initialized: bool = false;
} else struct {};

inline fn checkInitialized() void {
    if (std.builtin.mode == .Debug) {
        if (!initialized) {
            log.emerg("git is not initialized", .{});
            unreachable;
        }
    }
}

inline fn checkUninitialized() void {
    if (std.builtin.mode == .Debug) {
        if (initialized) {
            log.emerg("git is initialized", .{});
            unreachable;
        }
    }
}

comptime {
    std.testing.refAllDecls(@This());
}
