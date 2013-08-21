//
//  SRClip.m
//  SequenceRecord
//
//  Created by Jon Como on 8/5/13.
//  Copyright (c) 2013 Jon Como. All rights reserved.
//

#import "SRClip.h"
#import <AVFoundation/AVFoundation.h>

@implementation SRClip

-(id)initWithURL:(NSURL *)URL
{
    if (self = [super init]) {
        //init
        _URL = URL;
        
        [self generateThumbnail];
    }
    
    return self;
}

-(SRClip *)duplicate
{
    NSString *extension = [self.URL pathExtension];
    NSString *newPath = [NSString stringWithFormat:@"%@dup", [self.URL URLByDeletingPathExtension]];
    NSURL *newURL = [NSURL URLWithString:newPath];
    newURL = [newURL URLByAppendingPathExtension:extension];
    
    NSError *error;
    
    [[NSFileManager defaultManager] copyItemAtURL:self.URL toURL:newURL error:&error];
    
    SRClip *newClip;
    
    if (!error)
        newClip = [[SRClip alloc] initWithURL:newURL];
    
    return newClip;
}

-(void)setURL:(NSURL *)URL
{
    _URL = URL;
    
    [self generateThumbnail];
}

-(void)generateThumbnail
{
    [self generateThumbnailCompletion:^(UIImage *thumb) {
        _thumbnail = thumb;
        [[NSNotificationCenter defaultCenter] postNotificationName:SRClipNotificationDidGenerateThumbnail object:self];
    }];
}

-(void)generateThumbnailCompletion:(void (^)(UIImage *thumb))block
{
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:self.URL options:nil];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    
    CMTime thumbTime = CMTimeMakeWithSeconds(0,30);
    
    
    CGSize maxSize = CGSizeMake(100, 100);
    generator.maximumSize = maxSize;
    [generator generateCGImagesAsynchronouslyForTimes:[NSArray arrayWithObject:[NSValue valueWithCMTime:thumbTime]] completionHandler:^(CMTime requestedTime, CGImageRef image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError *error) {
        if (result != AVAssetImageGeneratorSucceeded) {
            NSLog(@"couldn't generate thumbnail, error:%@", error);
        }
        
        UIImage *thumb = [UIImage imageWithCGImage:image];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block)
                block(thumb);
        });
    }];
}

+(NSURL *)uniqueFileURLInDirectory:(NSString *)directory
{
    NSURL *returnURL;
    int counter = 0;
    
    do {
        returnURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/clip%i.mov", directory, counter]];
        counter ++;
    } while ([[NSFileManager defaultManager] fileExistsAtPath:[returnURL path]]);
    
    return returnURL;
}

@end
