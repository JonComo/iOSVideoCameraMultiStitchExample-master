//
// Copyright (c) 2013 Carson McDonald
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
// documentation files (the "Software"), to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
// and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions
// of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
// TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//

#import "VideoCameraInputManager.h"

#import "AVAssetStitcher.h"

#import <MobileCoreServices/UTCoreTypes.h>

@interface VideoCameraInputManager (Private) <UICollectionViewDataSource>

- (void)startNotificationObservers;
- (void)endNotificationObservers;

- (AVCaptureDevice *) cameraWithPosition:(AVCaptureDevicePosition) position;
- (AVCaptureDevice *) audioDevice;

- (AVCaptureConnection *)connectionWithMediaType:(NSString *)mediaType fromConnections:(NSArray *)connections;

- (NSString *)constructCurrentTemporaryFilename;
- (void)cleanTemporaryFiles;

@end

@implementation VideoCameraInputManager
{
    bool setupComplete;
    
    AVCaptureDeviceInput *videoInput;
    AVCaptureDeviceInput *audioInput;
    
    AVCaptureMovieFileOutput *movieFileOutput;
    
    AVCaptureVideoOrientation orientation;
    
    id deviceConnectedObserver;
    id deviceDisconnectedObserver;
    id deviceOrientationDidChangeObserver;
    
    long uniqueTimestamp;
    int currentRecordingSegment;
    
    CMTime currentFinalDurration;
    int inFlightWrites;
    
    BOOL isRecording;
}

- (id)initWithDelegate:(id<VideoCameraInputManagerDelegate>)managerDelegate
{
    if (self = [super init])
    {
        _delegate = managerDelegate;
        
        setupComplete = NO;
        
        _clips = [NSMutableArray array];
        
        currentRecordingSegment = 0;
        _isPaused = NO;
        _maxDuration = 0;
        inFlightWrites = 0;
        
        movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
        
        [self startNotificationObservers];
    }
    
    return self;
}

- (void)dealloc
{
    [_captureSession removeOutput:movieFileOutput];
    
    [self endNotificationObservers];
}

- (void)setupSessionWithPreset:(NSString *)preset withCaptureDevice:(AVCaptureDevicePosition)cd withTorchMode:(AVCaptureTorchMode)tm withError:(NSError **)error
{
    if(setupComplete)
    {
        *error = [NSError errorWithDomain:@"Setup session already complete." code:102 userInfo:nil];
        return;
    }
    
    setupComplete = YES;

	AVCaptureDevice *captureDevice = [self cameraWithPosition:cd];
    
	if ([captureDevice hasTorch])
    {
		if ([captureDevice lockForConfiguration:nil])
        {
			if ([captureDevice isTorchModeSupported:tm])
            {
				[captureDevice setTorchMode:AVCaptureTorchModeOff];
			}
			[captureDevice unlockForConfiguration];
		}
	}
    
    _captureSession = [[AVCaptureSession alloc] init];
    _captureSession.sessionPreset = preset;
    
    videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:captureDevice error:nil];
    if([_captureSession canAddInput:videoInput])
    {
        [_captureSession addInput:videoInput];
    }
    else
    {
        *error = [NSError errorWithDomain:@"Error setting video input." code:101 userInfo:nil];
        return;
    }

    audioInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self audioDevice] error:nil];
    if([_captureSession canAddInput:audioInput])
    {
        [_captureSession addInput:audioInput];
    }
    else
    {
        *error = [NSError errorWithDomain:@"Error setting audio input." code:101 userInfo:nil];
        return;
    }
    
    if([_captureSession canAddOutput:movieFileOutput])
    {
        [_captureSession addOutput:movieFileOutput];
    }
    else
    {
        *error = [NSError errorWithDomain:@"Error setting file output." code:101 userInfo:nil];
        return;
    }
}

-(void)flipCamera
{
    NSError *error;
    AVCaptureDeviceInput *newVideoInput;
    AVCaptureDevicePosition currentCameraPosition = [[videoInput device] position];
    
    if (currentCameraPosition == AVCaptureDevicePositionBack)
    {
        currentCameraPosition = AVCaptureDevicePositionFront;
    }
    else
    {
        currentCameraPosition = AVCaptureDevicePositionBack;
    }
    
    AVCaptureDevice *backFacingCamera = nil;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
	for (AVCaptureDevice *device in devices)
	{
		if ([device position] == currentCameraPosition)
		{
			backFacingCamera = device;
		}
	}
    
    newVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:backFacingCamera error:&error];
    
    if (newVideoInput != nil)
    {
        [_captureSession beginConfiguration];
        
        [_captureSession removeInput:videoInput];
        if ([_captureSession canAddInput:newVideoInput])
        {
            [_captureSession addInput:newVideoInput];
            videoInput = newVideoInput;
        }
        else
        {
            [_captureSession addInput:videoInput];
        }
        //captureSession.sessionPreset = oriPreset;
        [_captureSession commitConfiguration];
    }
}

- (void)startRecording
{
    isRecording = YES;
    
    [self.clips removeAllObjects];
    
    [self.collectionViewClips reloadData];
    
    uniqueTimestamp = [[NSDate date] timeIntervalSince1970];
    currentRecordingSegment = 0;
    _isPaused = NO;
    currentFinalDurration = kCMTimeZero;
    
    AVCaptureConnection *videoConnection = [self connectionWithMediaType:AVMediaTypeVideo fromConnections:movieFileOutput.connections];
    if ([videoConnection isVideoOrientationSupported])
    {
        videoConnection.videoOrientation = orientation;
    }
    
    NSURL *outputFileURL = [NSURL fileURLWithPath:[self constructCurrentTemporaryFilename]];
    
    movieFileOutput.maxRecordedDuration = (_maxDuration > 0) ? CMTimeMakeWithSeconds(_maxDuration, 600) : kCMTimeInvalid;
    
    [movieFileOutput startRecordingToOutputFileURL:outputFileURL recordingDelegate:self];
}

- (void)pauseRecording
{
    _isPaused = YES;
    
    [movieFileOutput stopRecording];
    
    currentFinalDurration = CMTimeAdd(currentFinalDurration, movieFileOutput.recordedDuration);
}

- (void)resumeRecording
{
    if (isRecording) return;
    
    isRecording = YES;
    currentRecordingSegment++;
    _isPaused = NO;
    
    NSURL *outputFileURL = [NSURL fileURLWithPath:[self constructCurrentTemporaryFilename]];
    
    if(_maxDuration > 0)
    {
        movieFileOutput.maxRecordedDuration = CMTimeSubtract(CMTimeMakeWithSeconds(_maxDuration, 600), currentFinalDurration);
    }
    else
    {
        movieFileOutput.maxRecordedDuration = kCMTimeInvalid;
    }
    
    [movieFileOutput startRecordingToOutputFileURL:outputFileURL recordingDelegate:self];
}

- (void)reset
{
    if (movieFileOutput.isRecording){
        [self pauseRecording];
    }
    
    _isPaused = NO;
    
    [self.clips removeAllObjects];
    [self.collectionViewClips reloadData];
}

-(void)thumbnailFromURL:(NSURL *)url completion:(void (^)(UIImage *thumb))block
{
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:url options:nil];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    
    CMTime thumbTime = CMTimeMakeWithSeconds(0,30);
    
    AVAssetImageGeneratorCompletionHandler handler = ^(CMTime requestedTime, CGImageRef im, CMTime actualTime, AVAssetImageGeneratorResult result, NSError *error)
    {
        
        if (result != AVAssetImageGeneratorSucceeded) {
            NSLog(@"couldn't generate thumbnail, error:%@", error);
        }
        
        UIImage *thumb = [UIImage imageWithCGImage:im];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block)
                block(thumb);
        });
    };

    CGSize maxSize = CGSizeMake(320, 180);
    generator.maximumSize = maxSize;
    [generator generateCGImagesAsynchronouslyForTimes:[NSArray arrayWithObject:[NSValue valueWithCMTime:thumbTime]] completionHandler:handler];
    
}

- (void)finalizeRecordingToFile:(NSURL *)finalVideoLocationURL withVideoSize:(CGSize)videoSize withPreset:(NSString *)preset withCompletionHandler:(void (^)(NSError *error))completionHandler
{
    //[self reset];
    
    NSError *error;
    if([finalVideoLocationURL checkResourceIsReachableAndReturnError:&error])
    {
        completionHandler([NSError errorWithDomain:@"Output file already exists." code:104 userInfo:nil]);
        return;
    }
    
    if(inFlightWrites != 0)
    {
        completionHandler([NSError errorWithDomain:@"Can't finalize recording unless all sub-recorings are finished." code:106 userInfo:nil]);
        return;
    }
    
    AVAssetStitcher *stitcher = [[AVAssetStitcher alloc] initWithOutputSize:videoSize];

    __block NSError *stitcherError;
    
    [self.clips enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        
        SRClip *clip = (SRClip *)obj;
        
        [stitcher addAsset:[AVURLAsset assetWithURL:clip.URL] withTransform:^CGAffineTransform(AVAssetTrack *videoTrack) {
            
            //
            // The following transform is applied to each video track. It changes the size of the
            // video so it fits within the output size and stays at the correct aspect ratio.
            //
            
            CGFloat ratioW = videoSize.width / videoTrack.naturalSize.width;
            CGFloat ratioH = videoSize.height / videoTrack.naturalSize.height;
            if(ratioW < ratioH)
            {
                // When the ratios are larger than one, we must flip the translation.
                float neg = (ratioH > 1.0) ? 1.0 : -1.0;
                CGFloat diffH = videoTrack.naturalSize.height - (videoTrack.naturalSize.height * ratioH);
                return CGAffineTransformConcat( CGAffineTransformMakeTranslation(0, neg*diffH/2.0), CGAffineTransformMakeScale(ratioH, ratioH) );
            }
            else
            {
                // When the ratios are larger than one, we must flip the translation.
                float neg = (ratioW > 1.0) ? 1.0 : -1.0;
                CGFloat diffW = videoTrack.naturalSize.width - (videoTrack.naturalSize.width * ratioW);
                return CGAffineTransformConcat( CGAffineTransformMakeTranslation(neg*diffW/2.0, 0), CGAffineTransformMakeScale(ratioW, ratioW) );
            }
            
        } withErrorHandler:^(NSError *error) {
            
            stitcherError = error;
            
        }];
    }];
    
    if(stitcherError){
        completionHandler(stitcherError);
        return;
    }
    
    [stitcher exportTo:finalVideoLocationURL withPreset:preset withCompletionHandler:^(NSError *error) {
        
        if(error){
            completionHandler(error);
        }else{
            //[self cleanTemporaryFiles];
            //[temporaryFileURLs removeAllObjects];
            
            completionHandler(nil);
        }
    }];
}

- (CMTime)totalRecordingDuration
{
    if(CMTimeCompare(kCMTimeZero, currentFinalDurration) == 0)
    {
        return movieFileOutput.recordedDuration;
    }
    else
    {
        CMTime returnTime = CMTimeAdd(currentFinalDurration, movieFileOutput.recordedDuration);
        return CMTIME_IS_INVALID(returnTime) ? currentFinalDurration : returnTime;
    }
}

#pragma mark - AVCaptureFileOutputRecordingDelegate implementation

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
    inFlightWrites++;
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
    if(error){
        if(self.asyncErrorHandler)
        {
            self.asyncErrorHandler(error);
        }
        else
        {
            NSLog(@"Error capturing output: %@", error);
        }
    }else{
        [self thumbnailFromURL:movieFileOutput.outputFileURL completion:^(UIImage *thumb) {
            SRClip *clip = [[SRClip alloc] initWithURL:fileURL thumbnail:thumb];
            [self.clips addObject:clip];
            
            if ([self.delegate respondsToSelector:@selector(videoCameraInputManager:addedClip:)])
                [self.delegate videoCameraInputManager:self addedClip:clip];
            
            [self.collectionViewClips reloadData];
            [self.collectionViewClips scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:MAX(0,self.clips.count-1) inSection:0] atScrollPosition:UICollectionViewScrollPositionRight animated:YES];
            
            isRecording = NO;
        }];
    }
    
    inFlightWrites--;
}

#pragma mark - Observer start and stop

- (void)startNotificationObservers
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    //
    // Reconnect to a device that was previously being used
    //
    deviceConnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasConnectedNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
        
        AVCaptureDevice *device = [notification object];
        
        NSString *deviceMediaType = nil;
        
        if ([device hasMediaType:AVMediaTypeAudio])
        {
            deviceMediaType = AVMediaTypeAudio;
        }
        else if ([device hasMediaType:AVMediaTypeVideo])
        {
            deviceMediaType = AVMediaTypeVideo;
        }
        
        if (deviceMediaType != nil)
        {
            [_captureSession.inputs enumerateObjectsUsingBlock:^(AVCaptureDeviceInput *input, NSUInteger idx, BOOL *stop) {
            
                if ([input.device hasMediaType:deviceMediaType])
                {
                    NSError	*error;
                    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
                    if ([_captureSession canAddInput:deviceInput])
                    {
                        [_captureSession addInput:deviceInput];
                    }
                    
                    if(error)
                    {
                        if(self.asyncErrorHandler)
                        {
                            self.asyncErrorHandler(error);
                        }
                        else
                        {
                            NSLog(@"Error reconnecting device input: %@", error);
                        }
                    }
                    
                    *stop = YES;
                }
            
            }];
        }
        
    }];
    
    //
    // Disable inputs from removed devices that are being used
    //
    deviceDisconnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasDisconnectedNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
        
        AVCaptureDevice *device = [notification object];
        
        if ([device hasMediaType:AVMediaTypeAudio])
        {
            [_captureSession removeInput:audioInput];
            audioInput = nil;
        }
        else if ([device hasMediaType:AVMediaTypeVideo])
        {
            [_captureSession removeInput:videoInput];
            videoInput = nil;
        }
        
    }];
    
    //
    // Track orientation changes. Note: This are pushed into the Quicktime video data and needs
    // to be used at decoding time to transform the video into the correct orientation.
    //
    orientation = AVCaptureVideoOrientationPortrait;
    deviceOrientationDidChangeObserver = [notificationCenter addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        
        switch ([[UIDevice currentDevice] orientation])
        {
            case UIDeviceOrientationPortrait:
                orientation = AVCaptureVideoOrientationPortrait;
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                orientation = AVCaptureVideoOrientationPortraitUpsideDown;
                break;
            case UIDeviceOrientationLandscapeLeft:
                orientation = AVCaptureVideoOrientationLandscapeRight;
                break;
            case UIDeviceOrientationLandscapeRight:
                orientation = AVCaptureVideoOrientationLandscapeLeft;
                break;
            default:
                orientation = AVCaptureVideoOrientationPortrait;
                break;
        }
        
    }];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
}

- (void)endNotificationObservers
{
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    
    [[NSNotificationCenter defaultCenter] removeObserver:deviceConnectedObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:deviceDisconnectedObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:deviceOrientationDidChangeObserver];
}

#pragma mark - Device finding methods

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition) position
{
    __block AVCaptureDevice *foundDevice = nil;
    
    [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] enumerateObjectsUsingBlock:^(AVCaptureDevice *device, NSUInteger idx, BOOL *stop) {
        
        if (device.position == position)
        {
            foundDevice = device;
            *stop = YES;
        }

    }];

    return foundDevice;
}

- (AVCaptureDevice *)audioDevice
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    if (devices.count > 0)
    {
        return devices[0];
    }
    return nil;
}

#pragma mark - Connection finding method

- (AVCaptureConnection *)connectionWithMediaType:(NSString *)mediaType fromConnections:(NSArray *)connections
{
    __block AVCaptureConnection *foundConnection = nil;
    
    [connections enumerateObjectsUsingBlock:^(AVCaptureConnection *connection, NSUInteger idx, BOOL *connectionStop) {
        
        [connection.inputPorts enumerateObjectsUsingBlock:^(AVCaptureInputPort *port, NSUInteger idx, BOOL *portStop) {
            
            if( [port.mediaType isEqual:mediaType] )
            {
				foundConnection = connection;
                
                *connectionStop = YES;
                *portStop = YES;
			}
            
        }];
        
    }];
    
	return foundConnection;
}

#pragma  mark - Temporary file handling functions

- (NSString *)constructCurrentTemporaryFilename
{
    return [NSString stringWithFormat:@"%@%@-%ld-%d.mov", NSTemporaryDirectory(), @"recordingsegment", uniqueTimestamp, currentRecordingSegment];
}

- (void)cleanTemporaryFiles
{
    for(SRClip *clip in self.clips)
    {
        [[NSFileManager defaultManager] removeItemAtURL:clip.URL error:nil];
    }
    
    [self.clips removeAllObjects];
}

#pragma UICollectionViewDataSourceDelegate

-(void)setCollectionViewClips:(UICollectionView *)collectionViewClips
{
    _collectionViewClips = collectionViewClips;
    
    collectionViewClips.dataSource = self;
}

-(UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"cellClip" forIndexPath:indexPath];
    
    SRClip *clip = [self.clips objectAtIndex:indexPath.row];
    
    UIImageView *imageView = (UIImageView *)[cell viewWithTag:100];
    
    imageView.image = clip.thumbnail;
    
    return cell;
}

-(NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.clips.count;
}

- (void)collectionView:(UICollectionView *)collectionView itemAtIndexPath:(NSIndexPath *)fromIndexPath didMoveToIndexPath:(NSIndexPath *)toIndexPath
{
    SRClip *clip = [self.clips objectAtIndex:fromIndexPath.item];
    [self.clips removeObjectAtIndex:fromIndexPath.item];
    [self.clips insertObject:clip atIndex:toIndexPath.item];
}

@end
