//
//  ADNFSApplication.m
//  ADNFS
//
//  Created by Keitaroh Kobayashi on 4/14/14.
//  Copyright (c) 2014 Keitaroh Kobayashi. All rights reserved.
//

#import "ADNFSApplication.h"

#import <ADNKit/ADNKit.h>

static const char *hello_str = "Hello World!\n";
static const char *hello_path = "/hello.txt";

static int adnfs_getattr(const char *path, struct stat *stbuf) {
    return [[ADNFSApplication sharedApplication] getAttrWithPath:path stat:stbuf];
}

static int adnfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                         off_t offset, struct fuse_file_info *fi) {
    
    return [[ADNFSApplication sharedApplication] readDirWithPath:path
                                                             buf:buf
                                                          filler:filler
                                                          offset:offset
                                                              fi:fi];
    
}

static int adnfs_open(const char *path, struct fuse_file_info *fi) {
    
    return [[ADNFSApplication sharedApplication] openPath:path
                                                       fi:fi];
    
}

static int adnfs_read(const char *path, char *buf, size_t size, off_t offset,
                      struct fuse_file_info *fi) {
    
    return [[ADNFSApplication sharedApplication] readPath:path
                                                      buf:buf
                                                     size:size
                                                   offset:offset
                                                       fi:fi];
}

@interface ADNFSApplication ()

@property (nonatomic, strong) ANKClient *client;

@end

@implementation ADNFSApplication {
    NSMutableDictionary *_cachedFiles;
    
    dispatch_queue_t fuseQueue;
}

#pragma mark - Singleton

+ (instancetype) sharedApplication {
    static dispatch_once_t pred;
    static ADNFSApplication *shared = nil;
    
    dispatch_once(&pred, ^{
        shared = [[ADNFSApplication alloc] init];
    });
    
    return shared;
}

#pragma mark - FUSE methods

- (int) getAttrWithPath:(const char *)_path
                   stat:(struct stat *)stbuf
{
    int res = 0;
    
    memset(stbuf, 0, sizeof(struct stat));
    
    NSString *path = [NSString stringWithUTF8String:_path];
    NSArray *pathComponents = path.pathComponents;
    
    if (pathComponents.count == 1 && [pathComponents[0] isEqualToString:@"/"]) {
        // At root level.
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
    } else if (pathComponents.count == 2 && pathComponents[1]) {
        ANKFile *file = _cachedFiles[pathComponents[1]];
        if (file) {
            stbuf->st_mode = S_IFREG | 0444;
            stbuf->st_nlink = 1;
            stbuf->st_size = file.sizeBytes;
            
            stbuf->st_mtime = stbuf->st_ctime = (long)file.createdAt.timeIntervalSince1970;
        } else {
            res = -ENOENT;
        }
    } else
        res = -ENOENT;
    
    return res;
}

- (int) readDirWithPath:(const char *)_path
                    buf:(void *) buf
                 filler:(fuse_fill_dir_t) filler
                 offset:(off_t) offset
                     fi:(struct fuse_file_info *)fi
{
    (void) offset;
	(void) fi;
    
    NSString *path = [NSString stringWithUTF8String:_path];
    
	if (![path isEqualToString:@"/"])
		return -ENOENT;
    
    filler(buf, ".", NULL, 0);
	filler(buf, "..", NULL, 0);
    
    for (NSString *filename in _cachedFiles) {
        filler(buf, filename.UTF8String, NULL, 0);
    }
    
	return 0;
}

- (int) openPath:(const char *)_path
              fi:(struct fuse_file_info *)fi
{
    NSString *path = [NSString stringWithUTF8String:_path];
    
    if ((fi->flags & 3) != O_RDONLY)
        return -EACCES;
    
    return 0;
}

- (int) readPath:(const char *)path
             buf:(char *)buf
            size:(size_t)size
          offset:(off_t)offset
              fi:(struct fuse_file_info *)fi
{
    size_t len;
    (void) fi;
    if(strcmp(path, hello_path) != 0)
        return -ENOENT;
    
    len = strlen(hello_str);
    if (offset < len) {
        if (offset + size > len)
            size = len - offset;
        memcpy(buf, hello_str + offset, size);
    } else
        size = 0;
    
    return (int)size;
}

- (void) runWithArgc:(int) argc
                argv:(char *[])argv
{
    
    static struct fuse_operations adnfs_oper = {
        .getattr	= adnfs_getattr,
        .readdir	= adnfs_readdir,
        .open		= adnfs_open,
        .read		= adnfs_read,
    };
    
    if (argc >= 1) {
        char * mountPath = argv[1];
        
        mkdir(mountPath, 0700);
    }

    fuseQueue = dispatch_queue_create("us.kkob.FuseQueue", NULL);
    _cachedFiles = @{}.mutableCopy;
    
    // Let's take the opportunity to authenticate with ADN now.
    self.client = [[ANKClient alloc] init];
    
    NSString *accessToken = nil;
#ifdef MANUAL_ACCESS_TOKEN
    accessToken = MANUAL_ACCESS_TOKEN;
#endif
    
    [self.client logInWithAccessToken:accessToken
                           completion:
     ^(BOOL succeeded, ANKAPIResponseMeta *meta, NSError *error) {
         if (succeeded) {
             dispatch_async(fuseQueue, ^{
                 [self preloadAllFiles];
                 
                 NSLog(@"Mounting...");
                 fuse_main(argc, argv, &adnfs_oper, NULL);
                 
                 NSLog(@"FUSE is done!");
             });
         } else {
             NSLog(@"Hm. The access token was rejected: %@", error.description);
         }
     }];
}

#pragma mark - ADN methods

- (void) preloadAllFiles {
    ANKClient *currentClient =
    [self.client clientWithPagination:[ANKPaginationSettings settingsWithCount:200]];

    __block BOOL isMore = YES;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    while (isMore) {
        [currentClient fetchCurrentUserFilesWithCompletion:
         ^(id responseObject, ANKAPIResponseMeta *meta, NSError *error) {
             NSArray *files = responseObject;
             for (ANKFile *file in files) {
                 _cachedFiles[file.name] = file;
             }
             
             currentClient.pagination.beforeID = meta.minID;
             isMore = meta.moreDataAvailable;
             
             dispatch_semaphore_signal(semaphore);
         }];
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }
}

@end