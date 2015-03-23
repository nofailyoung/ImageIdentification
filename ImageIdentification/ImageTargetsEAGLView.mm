//
//  ImageTargetsEAGLView.m
//  ImageIdentification
//
//  Created by 周俊杰 on 15/3/19.
//  Copyright (c) 2015年 北京金溪欣网络科技有限公司. All rights reserved.
//

#define NUM_VIDEO_TARGETS 11

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <sys/time.h>

#import <QCAR.h>
#import <State.h>
#import <Tool.h>
#import <Renderer.h>
#import <TrackableResult.h>
#import <VideoBackgroundConfig.h>
#import <ImageTarget.h>

#import "ImageTargetsEAGLView.h"
#import "Texture.h"
#import "SampleApplicationUtils.h"
#import "SampleApplicationShaderUtils.h"
#import "Teapot.h"
#import "Quad.h"
#include "SampleMath.h"

namespace {
    // --- Data private to this unit ---
    
    // Teapot texture filenames

    int touchedTarget = -1;
    // Model scale factor
    struct tagVideoData {
        // Needed to calculate whether a screen tap is inside the target
        QCAR::Matrix44F modelViewMatrix;
        
        // Trackable dimensions
        QCAR::Vec2F targetPositiveDimensions;
        
        // Currently active flag
        BOOL isActive;
    } videoData[NUM_VIDEO_TARGETS];
}

@interface ImageTargetsEAGLView () {
@private
    // OpenGL ES context
    EAGLContext *context;
    
    // The OpenGL ES names for the framebuffer and renderbuffers used to render
    // to this view
    GLuint defaultFramebuffer;
    GLuint colorRenderbuffer;
    GLuint depthRenderbuffer;
    
    // Shader handles
    GLuint shaderProgramID;
    GLint vertexHandle;
    GLint normalHandle;
    GLint textureCoordHandle;
    GLint mvpMatrixHandle;
    GLint texSampler2DHandle;
    
    // Texture used when rendering augmentation
    Texture* augmentationTexture;
    SampleApplication3DModel * buildingModel;
    
    SampleApplicationSession * vapp;
    NSLock* dataLock;

    float touchLocation_X;
    float touchLocation_Y;
}

@end
@implementation ImageTargetsEAGLView

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

- (id)initWithFrame:(CGRect)frame appSession:(SampleApplicationSession *) app
{
    self = [super initWithFrame:frame];
    
    if (self) {
        vapp = app;
        // Enable retina mode if available on this device
        if (YES == [vapp isRetinaDisplay]) {
            [self setContentScaleFactor:2.0f];
        }
        const char* textureFilenames = "playBtn.png";
        augmentationTexture = [[Texture alloc] initWithImageFile:[NSString stringWithCString:textureFilenames encoding:NSASCIIStringEncoding]];
        
        // Create the OpenGL ES context
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        // The EAGLContext must be set for each thread that wishes to use it.
        // Set it the first time this method is called (on the main thread)
        if (context != [EAGLContext currentContext]) {
            [EAGLContext setCurrentContext:context];
        }
        
        GLuint textureID;
        glGenTextures(1, &textureID);
        [augmentationTexture setTextureID:textureID];
        glBindTexture(GL_TEXTURE_2D, textureID);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, [augmentationTexture width], [augmentationTexture height], 0, GL_RGBA, GL_UNSIGNED_BYTE, (GLvoid*)[augmentationTexture pngData]);
        
        for (int i = 0; i < NUM_VIDEO_TARGETS; ++i) {
            videoData[i].targetPositiveDimensions.data[0] = 0.0f;
            videoData[i].targetPositiveDimensions.data[1] = 0.0f;
        }
        
        [self loadBuildingsModel];
        [self initShaders];
    }
    
    return self;
}

- (void) loadBuildingsModel {
    buildingModel = [[SampleApplication3DModel alloc] initWithTxtResourceName:@"buildings"];
    [buildingModel read];
}

#pragma mark - OpenGL ES management

- (void)initShaders
{
    shaderProgramID = [SampleApplicationShaderUtils createProgramWithVertexShaderFileName:@"Simple.vertsh"
                                                                   fragmentShaderFileName:@"Simple.fragsh"];
    
    if (0 < shaderProgramID) {
        vertexHandle = glGetAttribLocation(shaderProgramID, "vertexPosition");
        normalHandle = glGetAttribLocation(shaderProgramID, "vertexNormal");
        textureCoordHandle = glGetAttribLocation(shaderProgramID, "vertexTexCoord");
        mvpMatrixHandle = glGetUniformLocation(shaderProgramID, "modelViewProjectionMatrix");
        texSampler2DHandle  = glGetUniformLocation(shaderProgramID,"texSampler2D");
    }
    else {
        NSLog(@"Could not initialise augmentation shader");
    }
}

#pragma mark - UIGLViewProtocol
- (void)renderFrameQCAR
{
    [self setFramebuffer];
    
    // Clear colour and depth buffers
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    // Render video background and retrieve tracking state
    QCAR::State state = QCAR::Renderer::getInstance().begin();
    QCAR::Renderer::getInstance().drawVideoBackground();
    
    glEnable(GL_DEPTH_TEST);
    // We must detect if background reflection is active and adjust the culling direction.
    // If the reflection is active, this means the pose matrix has been reflected as well,
    // therefore standard counter clockwise face culling will result in "inside out" models.
    glEnable(GL_CULL_FACE);

    glCullFace(GL_BACK);
    if(QCAR::Renderer::getInstance().getVideoBackgroundConfig().mReflection == QCAR::VIDEO_BACKGROUND_REFLECTION_ON) {
        // Front camera
        glFrontFace(GL_CW);
    }
    else {
        // Back camera
        glFrontFace(GL_CCW);
    }

    [dataLock lock];
    for (int i = 0; i < NUM_VIDEO_TARGETS; ++i) {
        videoData[i].isActive = NO;
    }
    
    for (int i = 0; i < state.getNumTrackableResults(); ++i) {
        // Get the trackable
        const QCAR::TrackableResult* result = state.getTrackableResult(i);
        const QCAR::ImageTarget& imageTarget = (const QCAR::ImageTarget&) result->getTrackable();

        int playerIndex = -1;
        if (strcmp(imageTarget.getName(), "0") == 0)
        {
            playerIndex = 0;
        }else if (strcmp(imageTarget.getName(), "01") == 0) {
            playerIndex = 1;
        }else if (strcmp(imageTarget.getName(), "02") == 0) {
            playerIndex = 2;
        }else if (strcmp(imageTarget.getName(), "03") == 0) {
            playerIndex = 3;
        }else if (strcmp(imageTarget.getName(), "04") == 0) {
            playerIndex = 4;
        }else if (strcmp(imageTarget.getName(), "05") == 0) {
            playerIndex = 5;
        }else if (strcmp(imageTarget.getName(), "06") == 0) {
            playerIndex = 6;
        }else if (strcmp(imageTarget.getName(), "07") == 0) {
            playerIndex = 7;
        }else if (strcmp(imageTarget.getName(), "08") == 0) {
            playerIndex = 8;
        }else if (strcmp(imageTarget.getName(), "09") == 0) {
            playerIndex = 9;
        }else if (strcmp(imageTarget.getName(), "10") == 0) {
            playerIndex = 10;
        }else if (strcmp(imageTarget.getName(), "11") == 0) {
            playerIndex = 11;
        }
        
        videoData[playerIndex].isActive = YES;
        
        if (0.0f == videoData[playerIndex].targetPositiveDimensions.data[0] ||
            0.0f == videoData[playerIndex].targetPositiveDimensions.data[1]) {
            const QCAR::ImageTarget& imageTarget = (const QCAR::ImageTarget&) result->getTrackable();
            
            QCAR::Vec3F size = imageTarget.getSize();
            videoData[playerIndex].targetPositiveDimensions.data[0] = size.data[0];
            videoData[playerIndex].targetPositiveDimensions.data[1] = size.data[1];
            
            // The pose delivers the centre of the target, thus the dimensions
            // go from -width / 2 to width / 2, and -height / 2 to height / 2
            videoData[playerIndex].targetPositiveDimensions.data[0] /= 2.0f;
            videoData[playerIndex].targetPositiveDimensions.data[1] /= 2.0f;
        }

        //const QCAR::Trackable& trackable = result->getTrackable();
        const QCAR::Matrix34F& trackablePose = result->getPose();
        videoData[playerIndex].modelViewMatrix = QCAR::Tool::convertPose2GLMatrix(trackablePose);
        // OpenGL 2

        QCAR::Matrix44F projMatrix = vapp.projectionMatrix;
        
        QCAR::Matrix44F modelViewMatrixButton = QCAR::Tool::convertPose2GLMatrix(trackablePose);
        QCAR::Matrix44F modelViewProjectionButton;
        
        SampleApplicationUtils::translatePoseMatrix(0.0f, 0.0f, 2.0f, &modelViewMatrixButton.data[0]);
        
        SampleApplicationUtils::scalePoseMatrix(videoData[playerIndex].targetPositiveDimensions.data[1]/2,
                                                videoData[playerIndex].targetPositiveDimensions.data[1]/2,
                                                videoData[playerIndex].targetPositiveDimensions.data[1]/2,
                                                &modelViewMatrixButton.data[0]);
        
        SampleApplicationUtils::multiplyMatrix(projMatrix.data,
                                               &modelViewMatrixButton.data[0] ,
                                               &modelViewProjectionButton.data[0]);
        glDepthFunc(GL_LEQUAL);
        glUseProgram(shaderProgramID);
        
        glVertexAttribPointer(vertexHandle, 3, GL_FLOAT, GL_FALSE, 0, quadVertices);
        glVertexAttribPointer(normalHandle, 3, GL_FLOAT, GL_FALSE, 0, quadNormals);
        glVertexAttribPointer(textureCoordHandle, 2, GL_FLOAT, GL_FALSE, 0, quadTexCoords);
        
        glEnableVertexAttribArray(vertexHandle);
        glEnableVertexAttribArray(normalHandle);
        glEnableVertexAttribArray(textureCoordHandle);
        
        // Choose the texture based on the target name
        GLuint iconTextureID = [augmentationTexture textureID];
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, iconTextureID);
        glUniformMatrix4fv(mvpMatrixHandle, 1, GL_FALSE, (const GLfloat*)&modelViewProjectionButton.data[0]);
        glUniform1i(texSampler2DHandle, 0 /*GL_TEXTURE0*/);

        glDrawElements(GL_TRIANGLES, NUM_QUAD_INDEX, GL_UNSIGNED_SHORT, quadIndices);
        
        glDisable(GL_BLEND);
        glDisableVertexAttribArray(vertexHandle);
        glDisableVertexAttribArray(normalHandle);
        glDisableVertexAttribArray(textureCoordHandle);

        glUseProgram(0);
        
        glDepthFunc(GL_LESS);
        
        SampleApplicationUtils::checkGlError("EAGLView renderFrameQCAR");

//        dispatch_async(dispatch_get_main_queue(), ^{
//            UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(150, 150, 50, 50)];
//            lab.text = @"play";
//            lab.backgroundColor = [UIColor redColor];
//            [self addSubview:lab];
//        });
    }
    [dataLock unlock];

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    
    QCAR::Renderer::getInstance().end();
    [self presentFramebuffer];
}

- (void)setFramebuffer
{
    // The EAGLContext must be set for each thread that wishes to use it.  Set
    // it the first time this method is called (on the render thread)
    if (context != [EAGLContext currentContext]) {
        [EAGLContext setCurrentContext:context];
    }
    
    if (!defaultFramebuffer) {
        // Perform on the main thread to ensure safe memory allocation for the
        // shared buffer.  Block until the operation is complete to prevent
        // simultaneous access to the OpenGL context
        [self performSelectorOnMainThread:@selector(createFramebuffer) withObject:self waitUntilDone:YES];
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
}

- (BOOL)presentFramebuffer
{
    // setFramebuffer must have been called before presentFramebuffer, therefore
    // we know the context is valid and has been set for this (render) thread
    
    // Bind the colour render buffer and present it
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    
    return [context presentRenderbuffer:GL_RENDERBUFFER];
}

- (void)createFramebuffer
{
    if (context) {
        // Create default framebuffer object
        glGenFramebuffers(1, &defaultFramebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
        
        // Create colour renderbuffer and allocate backing store
        glGenRenderbuffers(1, &colorRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        
        // Allocate the renderbuffer's storage (shared with the drawable object)
        [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
        GLint framebufferWidth;
        GLint framebufferHeight;
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight);
        
        // Create the depth render buffer and allocate storage
        glGenRenderbuffers(1, &depthRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, framebufferWidth, framebufferHeight);
        
        // Attach colour and depth render buffers to the frame buffer
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
        
        // Leave the colour render buffer bound so future rendering operations will act on it
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    }
}

#pragma mark - SampleGLResourceHandler
- (void)freeOpenGLESResources
{
    // Called in response to applicationDidEnterBackground.  Free easily
    // recreated OpenGL ES resources
    [self deleteFramebuffer];
    glFinish();
}

- (void)deleteFramebuffer
{
    if (context) {
        [EAGLContext setCurrentContext:context];
        
        if (defaultFramebuffer) {
            glDeleteFramebuffers(1, &defaultFramebuffer);
            defaultFramebuffer = 0;
        }
        
        if (colorRenderbuffer) {
            glDeleteRenderbuffers(1, &colorRenderbuffer);
            colorRenderbuffer = 0;
        }
        
        if (depthRenderbuffer) {
            glDeleteRenderbuffers(1, &depthRenderbuffer);
            depthRenderbuffer = 0;
        }
    }
}

- (void)finishOpenGLESCommands
{
    // Called in response to applicationWillResignActive.  The render loop has
    // been stopped, so we now make sure all OpenGL ES commands complete before
    // we (potentially) go into the background
    if (context) {
        [EAGLContext setCurrentContext:context];
        glFinish();
    }
}

#pragma mark - User interaction

- (int) handleTouchPoint:(CGPoint) point {
    // Store the current touch location
    touchLocation_X = point.x;
    touchLocation_Y = point.y;
    
    // Determine which target was touched (if no target was touch, touchedTarget
    // will be -1)
    touchedTarget = [self tapInsideTargetWithID];
    return touchedTarget;
}

- (int)tapInsideTargetWithID
{
    QCAR::Vec3F intersection, lineStart, lineEnd;
    // Get the current projection matrix
    QCAR::Matrix44F projectionMatrix = [vapp projectionMatrix];
    QCAR::Matrix44F inverseProjMatrix = SampleMath::Matrix44FInverse(projectionMatrix);
    CGRect rect = [self bounds];
    int touchInTarget = -1;
    
    // ----- Synchronise data access -----
    [dataLock lock];
    
    // The target returns as pose the centre of the trackable.  Thus its
    // dimensions go from -width / 2 to width / 2 and from -height / 2 to
    // height / 2.  The following if statement simply checks that the tap is
    // within this range
    for (int i = 0; i < NUM_VIDEO_TARGETS; ++i) {
        SampleMath::projectScreenPointToPlane(inverseProjMatrix, videoData[i].modelViewMatrix, rect.size.width, rect.size.height,QCAR::Vec2F(touchLocation_X, touchLocation_Y), QCAR::Vec3F(0, 0, 0), QCAR::Vec3F(0, 0, 1), intersection, lineStart, lineEnd);
        
        if ((intersection.data[0] >= -videoData[i].targetPositiveDimensions.data[0]) && (intersection.data[0] <= videoData[i].targetPositiveDimensions.data[0]) &&
            (intersection.data[1] >= -videoData[i].targetPositiveDimensions.data[1]) && (intersection.data[1] <= videoData[i].targetPositiveDimensions.data[1])) {
            // The tap is only valid if it is inside an active target
            if (YES == videoData[i].isActive) {
                touchInTarget = i;
                break;
            }
        }
    }
    
    [dataLock unlock];
    // ----- End synchronise data access -----
    
    return touchInTarget;
}

@end
