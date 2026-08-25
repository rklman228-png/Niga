#import "NigaMobileGestaltLocator.h"

#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach-o/loader.h>
#import <stdint.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

static char gLocatorDiagnostics[4096] = "locator not run";

static void NigaSetDiag(NSString *text)
{
    const char *utf8 = text.UTF8String ?: "locator diagnostics unavailable";
    snprintf(gLocatorDiagnostics, sizeof(gLocatorDiagnostics), "%s", utf8);
}

static BOOL NigaPointerMatches(uintptr_t candidate, uintptr_t target)
{
    if (candidate == target) return YES;

    // arm64e authenticated/data pointers can carry non-address bits in the high
    // portion. MobileGestalt metadata ultimately points at the same __cstring
    // address, so compare the canonical low VA bits as a PAC-tolerant fallback.
    const uintptr_t low48 = 0x0000FFFFFFFFFFFFULL;
    if ((candidate & low48) == (target & low48)) return YES;

    // Also tolerate top-byte tags without throwing away bits 48-55.
    const uintptr_t low56 = 0x00FFFFFFFFFFFFFFULL;
    return (candidate & low56) == (target & low56);
}

static const struct mach_header_64 *NigaFindMobileGestaltHeader(intptr_t *slideOut)
{
    const char *wanted = "libMobileGestalt.dylib";
    dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW | RTLD_GLOBAL);

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        const char *base = strrchr(name, '/');
        base = base ? base + 1 : name;
        if (strcmp(base, wanted) == 0) {
            if (slideOut) *slideOut = _dyld_get_image_vmaddr_slide(i);
            return (const struct mach_header_64 *)_dyld_get_image_header(i);
        }
    }
    return NULL;
}

static const char *NigaFindCString(const struct mach_header_64 *header,
                                   intptr_t slide,
                                   const char *key,
                                   NSString **whereOut)
{
    unsigned long cstringSize = 0;
    uint8_t *cstring = getsectiondata(header, "__TEXT", "__cstring", &cstringSize);
    if (cstring && cstringSize) {
        const char *cursor = (const char *)cstring;
        const char *end = cursor + cstringSize;
        while (cursor < end) {
            size_t remaining = (size_t)(end - cursor);
            size_t len = strnlen(cursor, remaining);
            if (len >= remaining) break;
            if (strcmp(cursor, key) == 0) {
                if (whereOut) *whereOut = @"__TEXT,__cstring";
                return cursor;
            }
            cursor += len + 1;
        }
    }

    // Fallback for builds that move cstring literals between TEXT sections.
    const uint8_t *lcPtr = (const uint8_t *)(header + 1);
    for (uint32_t c = 0; c < header->ncmds; c++) {
        const struct load_command *lc = (const struct load_command *)lcPtr;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strncmp(seg->segname, "__TEXT", 16) == 0) {
                const struct section_64 *sections = (const struct section_64 *)(seg + 1);
                for (uint32_t s = 0; s < seg->nsects; s++) {
                    const struct section_64 *sect = &sections[s];
                    if ((sect->flags & SECTION_TYPE) != S_CSTRING_LITERALS || sect->size == 0) continue;
                    const uint8_t *bytes = (const uint8_t *)(uintptr_t)(sect->addr + slide);
                    size_t size = (size_t)sect->size;
                    size_t keyLen = strlen(key);
                    if (size <= keyLen) continue;
                    for (size_t p = 0; p + keyLen < size; p++) {
                        if (bytes[p] == (uint8_t)key[0] &&
                            memcmp(bytes + p, key, keyLen) == 0 &&
                            bytes[p + keyLen] == 0) {
                            if (whereOut) {
                                *whereOut = [NSString stringWithFormat:@"%.*s,%.*s", 16, seg->segname, 16, sect->sectname];
                            }
                            return (const char *)(bytes + p);
                        }
                    }
                }
            }
        }
        if (lc->cmdsize == 0) break;
        lcPtr += lc->cmdsize;
    }
    return NULL;
}

size_t niga_mg_cache_data_offset(const char *key, size_t cacheDataLength)
{
    @autoreleasepool {
        if (!key || !*key || cacheDataLength < sizeof(uint64_t)) {
            NigaSetDiag(@"invalid key or CacheData length");
            return 0;
        }

        intptr_t slide = 0;
        const struct mach_header_64 *header = NigaFindMobileGestaltHeader(&slide);
        if (!header) {
            NigaSetDiag(@"libMobileGestalt.dylib is not present in dyld image list");
            return 0;
        }

        NSString *cstringWhere = nil;
        const char *keyPtr = NigaFindCString(header, slide, key, &cstringWhere);
        if (!keyPtr) {
            NigaSetDiag([NSString stringWithFormat:@"key %s not found in MobileGestalt cstring sections", key]);
            return 0;
        }

        uintptr_t target = (uintptr_t)keyPtr;
        NSUInteger pointerMatches = 0;
        NSUInteger plausibleSlots = 0;
        NSMutableArray<NSString *> *locations = [NSMutableArray array];

        const uint8_t *lcPtr = (const uint8_t *)(header + 1);
        for (uint32_t c = 0; c < header->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)lcPtr;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                BOOL interesting = strncmp(seg->segname, "__AUTH_CONST", 16) == 0 ||
                                   strncmp(seg->segname, "__DATA_CONST", 16) == 0 ||
                                   strncmp(seg->segname, "__AUTH", 16) == 0 ||
                                   strncmp(seg->segname, "__DATA", 16) == 0;
                if (interesting) {
                    const struct section_64 *sections = (const struct section_64 *)(seg + 1);
                    for (uint32_t s = 0; s < seg->nsects; s++) {
                        const struct section_64 *sect = &sections[s];
                        if (sect->size < sizeof(uintptr_t)) continue;
                        const uint8_t *bytes = (const uint8_t *)(uintptr_t)(sect->addr + slide);
                        size_t size = (size_t)sect->size;

                        for (size_t p = 0; p + sizeof(uintptr_t) <= size; p += sizeof(uintptr_t)) {
                            uintptr_t candidate = 0;
                            memcpy(&candidate, bytes + p, sizeof(candidate));
                            if (!NigaPointerMatches(candidate, target)) continue;
                            pointerMatches++;

                            // Mond's current metadata layout stores the CacheData
                            // slot index 0x9a bytes after the key-pointer field.
                            if (p + 0x9a + sizeof(uint16_t) > size) continue;
                            uint16_t slot = 0;
                            memcpy(&slot, bytes + p + 0x9a, sizeof(slot));
                            size_t offset = ((size_t)slot) << 3;
                            if (offset == 0 || offset + sizeof(uint64_t) > cacheDataLength) continue;

                            plausibleSlots++;
                            NSString *loc = [NSString stringWithFormat:@"%.*s,%.*s+0x%zx -> slot=%u offset=%zu",
                                             16, seg->segname, 16, sect->sectname, p, slot, offset];
                            [locations addObject:loc];

                            NigaSetDiag([NSString stringWithFormat:
                                @"PASS\nkey: %s\ncstring: %@ @ %p\nCacheData length: %zu\npointer matches: %lu\nselected: %@",
                                key, cstringWhere ?: @"unknown", keyPtr, cacheDataLength,
                                (unsigned long)pointerMatches, loc]);
                            return offset;
                        }
                    }
                }
            }
            if (lc->cmdsize == 0) break;
            lcPtr += lc->cmdsize;
        }

        NigaSetDiag([NSString stringWithFormat:
            @"FAILED\nkey: %s\ncstring: %@ @ %p\nCacheData length: %zu\npointer matches after PAC-tolerant scan: %lu\nplausible slots: %lu\nNo safe DeviceClassNumber metadata record was found.",
            key, cstringWhere ?: @"unknown", keyPtr, cacheDataLength,
            (unsigned long)pointerMatches, (unsigned long)plausibleSlots]);
        return 0;
    }
}

char *niga_mg_copy_locator_diagnostics(void)
{
    return strdup(gLocatorDiagnostics);
}

void niga_mg_free_locator_string(char *value)
{
    if (value) free(value);
}
