//
//  SRClip.m
//  SequenceRecord
//
//  Created by Jon Como on 8/5/13.
//  Copyright (c) 2013 Jon Como. All rights reserved.
//

#import "SRClip.h"

@implementation SRClip

-(id)initWithURL:(NSURL *)URL thumbnail:(UIImage *)thumbnail
{
    if (self = [super init]) {
        //init
        _URL = URL;
        _thumbnail = thumbnail;
    }
    
    return self;
}

@end
