//
//  KMVideoTool.m
//  AIBasicModule
//
//  Created by 刘畅 on 2022/4/12.
//

#import "KMVideoTool.h"
#import <CoreServices/CoreServices.h>
#import <AVFoundation/AVFoundation.h>

@implementation KMVideoTool
+ (CGSize)sizeWithVideoURL:(NSURL *)videoURL {
    AVAsset *videoAsset = [AVAsset assetWithURL:videoURL];
    AVAssetTrack *videoTrack = [videoAsset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (videoTrack) {
        return videoTrack.naturalSize;
    } else {
        return CGSizeZero;
    }
}

+ (UIImage *)thumbImage:(NSURL *)videoURL {
    NSDictionary *opts = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO] forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
    AVURLAsset *urlAsset = [AVURLAsset URLAssetWithURL:videoURL options:opts];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:urlAsset];
    generator.appliesPreferredTrackTransform = YES;
    CMTime actualTime;
    NSError *error = nil;
    CGImageRef img = [generator copyCGImageAtTime:CMTimeMake(0, 600) actualTime:&actualTime error:&error];
    if (error) {
        return nil;
    }
    return [UIImage imageWithCGImage:img];
}

+ (NSInteger)durationWithvideoURL:(NSURL *)videoURL {
    NSDictionary *opts = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO] forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
    AVURLAsset *urlAsset = [AVURLAsset URLAssetWithURL:videoURL options:opts];
    return urlAsset.duration.value / urlAsset.duration.timescale;
}

+ (void)compressWithVideoURL:(NSURL *)videoURL
                   outputURL:(NSURL *)outputURL
                         fps:(NSInteger)fps             // 24
                     bitRate:(NSInteger)bitRate         // 200 * 8 * 1024
              dimensionScale:(CGFloat)dimensionScale
                  completion:(void(^)(BOOL success))completion {
    if (!videoURL.absoluteString.length ||
        !outputURL.absoluteString.length ||
        dimensionScale <= 0 ||
        fps <= 10) {
        return;
    }
    AVAsset *videoAsset = [AVAsset assetWithURL:videoURL];
    
    NSError *readerError;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:videoAsset error:&readerError];
    NSError *writerError;
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:outputURL fileType:AVFileTypeMPEG4 error:&writerError];
    
    
    // video
    AVAssetTrack *videoTrack = [videoAsset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    AVAssetWriterInput *videoInput;
    AVAssetReaderOutput *videoOutput;
    if (videoTrack) {
        //    NSDictionary *videoOutputSetting = @{(id) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
        NSDictionary *videoOutputSetting = @{
              (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_422YpCbCr8]
            };
            
        videoOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:videoOutputSetting];
        
        NSDictionary *videoCompressProperties = @{
            AVVideoAverageBitRateKey : @(bitRate),        // 200 * 8 * 1024
            AVVideoExpectedSourceFrameRateKey : @(fps),   // 24
            AVVideoProfileLevelKey : AVVideoProfileLevelH264HighAutoLevel
        };
        
        CGSize videoSize = [self sizeWithVideoURL:videoURL];
        CGFloat videoWidth = videoSize.width;
        CGFloat videoHeight = videoSize.height;
        NSDictionary *videoCompressSettings = @{
            AVVideoCodecKey : AVVideoCodecTypeH264,
            AVVideoWidthKey : @(videoWidth * dimensionScale),
            AVVideoHeightKey :@(videoHeight * dimensionScale),
            AVVideoCompressionPropertiesKey : videoCompressProperties,
            AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill
        };
        
        videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoCompressSettings];
        videoInput.transform = videoTrack.preferredTransform;
        if ([reader canAddOutput:videoOutput]) {
            [reader addOutput:videoOutput];
        }
        
        if ([writer canAddInput:videoInput]) {
            [writer addInput:videoInput];
        }
    }
    
    // audio
    AVAssetTrack *audioTrack = [videoAsset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    AVAssetReaderTrackOutput *audioOutput;
    AVAssetWriterInput *audioInput;
    if (audioTrack) {
        NSDictionary *audioOutputSetting = @{
                                                 AVFormatIDKey: @(kAudioFormatLinearPCM)
                                                 };
        audioOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTrack outputSettings:audioOutputSetting];
        
        AudioChannelLayout audioChannelLayout = {
            .mChannelLayoutTag = kAudioChannelLayoutTag_Stereo,
            .mChannelBitmap = 0,
            .mNumberChannelDescriptions = 0
        };
        
        NSData *channelLayoutAsData = [NSData dataWithBytes:&audioChannelLayout length:offsetof(AudioChannelLayout, mChannelDescriptions)];

        NSDictionary *audioCompressSettings = @{
            AVFormatIDKey : @(kAudioFormatMPEG4AAC),
            AVEncoderBitRateKey : @(96000),
            AVSampleRateKey :@(44100),
            AVChannelLayoutKey : channelLayoutAsData,
            AVNumberOfChannelsKey : @(2)
        };
        
        audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioCompressSettings];
        
        if ([reader canAddOutput:audioOutput]) {
            [reader addOutput:audioOutput];
        }
        
        if ([writer canAddInput:audioInput]) {
            [writer addInput:audioInput];
        }
    }
    
    [reader startReading];
    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];
    
    dispatch_group_t group = dispatch_group_create();
    
    if (videoInput && videoOutput) {
        dispatch_group_enter(group);
        dispatch_queue_t videoCompressQueue = dispatch_queue_create("videoCompressQueue", NULL);
        [videoInput requestMediaDataWhenReadyOnQueue:videoCompressQueue usingBlock:^{
            while ([videoInput isReadyForMoreMediaData]) {
                CMSampleBufferRef sampleBuffer;
                if (reader.status == AVAssetReaderStatusReading &&
                    (sampleBuffer = [videoOutput copyNextSampleBuffer])) {
                    BOOL result = [videoInput appendSampleBuffer:sampleBuffer];
                    CFRelease(sampleBuffer);
                    if (!result) {
                        [reader cancelReading];
                        break;
                    }
                } else {
                    [videoInput markAsFinished];
                    dispatch_group_leave(group);
                    break;
                }
            }
        }];
    }
    
    
    if (audioInput && audioOutput) {
        dispatch_group_enter(group);
        dispatch_queue_t audioCompressQueue = dispatch_queue_create("audioCompressQueue", NULL);
        [audioInput requestMediaDataWhenReadyOnQueue:audioCompressQueue usingBlock:^{
            while ([audioInput isReadyForMoreMediaData]) {
                CMSampleBufferRef sampleBuffer;
                if (reader.status == AVAssetReaderStatusReading &&
                    (sampleBuffer = [audioOutput copyNextSampleBuffer])) {
                    BOOL result = [audioInput appendSampleBuffer:sampleBuffer];
                    CFRelease(sampleBuffer);
                    if (!result) {
                        [reader cancelReading];
                        break;
                    }
                } else {
                    [audioInput markAsFinished];
                    dispatch_group_leave(group);
                    break;
                }
            }
        }];
    }
    
    dispatch_group_notify(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (reader.status == AVAssetReaderStatusReading) {
            [reader cancelReading];
        }
        switch (writer.status) {
            case AVAssetWriterStatusWriting:
            {
                [writer finishWritingWithCompletionHandler:^{
                    if (completion) {
                        completion(YES);
                    }
                }];
            }
                break;
            case AVAssetWriterStatusFailed:
            case AVAssetWriterStatusCancelled:
            case AVAssetWriterStatusUnknown:
            {
                if (completion) {
                    completion(NO);
                }
            }
                break;
            default:
                break;
        }
    });
}
@end
