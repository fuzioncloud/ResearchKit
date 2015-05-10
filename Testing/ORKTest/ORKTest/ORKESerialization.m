/*
 Copyright (c) 2015, Apple Inc. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 1.  Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2.  Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.
 
 3.  Neither the name of the copyright holder(s) nor the names of any contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission. No license is granted to the trademarks of
 the copyright holders even if such marks are included in this software.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


#import "ORKESerialization.h"


static NSString *ORKEStringFromDateISO8601(NSDate *date) {
    static NSDateFormatter *__formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __formatter = [[NSDateFormatter alloc] init];
        [__formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
        [__formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    });
    return [__formatter stringFromDate:date];
}

static NSDate *ORKEDateFromStringISO8601(NSString *string) {
    static NSDateFormatter *__formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __formatter = [[NSDateFormatter alloc] init];
        [__formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
        [__formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    });
    return [__formatter dateFromString:string];
}

static NSArray *ORKNumericAnswerStyleTable() {
    static NSArray *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = @[@"decimal", @"integer"];
    });
    return table;
}

static id tableMapForward(NSInteger index, NSArray *table) {
    return table[index];
}

static NSInteger tableMapReverse(id value, NSArray *table) {
    NSUInteger idx = [table indexOfObject:value];
    if (idx == NSNotFound)
    {
        idx = 0;
    }
    return idx;
}

static NSDictionary *dictionaryFromCGPoint(CGPoint p) {
    return @{ @"x" : @(p.x), @"y" : @(p.y) };
}

static NSDictionary *dictionaryFromCGSize(CGSize s) {
    return @{ @"h" : @(s.width), @"w" : @(s.width) };
}

static NSDictionary *dictionaryFromCGRect(CGRect r) {
    return @{ @"origin" : dictionaryFromCGPoint(r.origin), @"size" : dictionaryFromCGSize(r.size) };
}

static CGSize sizeFromDictionary(NSDictionary *dict) {
    return (CGSize){.width = [dict[@"w"] doubleValue], .height = [dict[@"h"] doubleValue] };
}

static CGPoint pointFromDictionary(NSDictionary *dict) {
    return (CGPoint){.x = [dict[@"x"] doubleValue], .y = [dict[@"y"] doubleValue]};
}

static CGRect rectFromDictionary(NSDictionary *dict) {
    return (CGRect){.origin = pointFromDictionary(dict[@"origin"]), .size = sizeFromDictionary(dict[@"size"])};
}

static ORKNumericAnswerStyle ORKNumericAnswerStyleFromString(NSString *s) {
    return tableMapReverse(s, ORKNumericAnswerStyleTable());
}

static NSString *ORKNumericAnswerStyleToString(ORKNumericAnswerStyle style) {
    return tableMapForward(style, ORKNumericAnswerStyleTable());
}

static NSMutableDictionary *ORKESerializationEncodingTable();
static id propFromDict(NSDictionary *dict, NSString *propName);
static NSArray *classEncodingsForClass(Class c) ;
static id objectForJsonObject(id input, Class expectedClass, ORKESerializationJSONToObjectBlock converterBlock) ;

#define ESTRINGIFY2( x) #x
#define ESTRINGIFY(x) ESTRINGIFY2(x)

#define ENTRY(entryName, bb, props) @ESTRINGIFY(entryName) : [[ORKESerializableTableEntry alloc] initWithClass:[entryName class] initBlock:bb properties: props]

#define PROPERTY(x, vc, cc, ww, jb, ob) @ESTRINGIFY(x) : ([[ORKESerializableProperty alloc] initWithPropertyName:@ESTRINGIFY(x) valueClass:[vc class] containerClass:[cc class] writeAfterInit:ww objectToJSONBlock:jb jsonToObjectBlock:ob ])


#define DYNAMICCAST(x, c) ((c *) ([x isKindOfClass:[c class]] ? x : nil))


@interface ORKESerializableTableEntry : NSObject

- (instancetype)initWithClass:(Class)class
                    initBlock:(ORKESerializationInitBlock)initBlock
                   properties:(NSDictionary *)properties;

@property (nonatomic) Class class;
@property (nonatomic, copy) ORKESerializationInitBlock initBlock;
@property (nonatomic, strong) NSMutableDictionary *properties;

@end


@interface ORKESerializableProperty : NSObject

- (instancetype)initWithPropertyName:(NSString *)propertyName
                          valueClass:(Class)valueClass
                      containerClass:(Class)containerClass
                      writeAfterInit:(BOOL)writeAfterInit
                   objectToJSONBlock:(ORKESerializationObjectToJSONBlock)objectToJSON
                   jsonToObjectBlock:(ORKESerializationJSONToObjectBlock)jsonToObjectBlock;

@property (nonatomic, copy) NSString *propertyName;
@property (nonatomic) Class valueClass;
@property (nonatomic) Class containerClass;
@property (nonatomic) BOOL writeAfterInit;
@property (nonatomic, copy) ORKESerializationObjectToJSONBlock objectToJSONBlock;
@property (nonatomic, copy) ORKESerializationJSONToObjectBlock jsonToObjectBlock;

@end


@implementation ORKESerializableTableEntry

- (instancetype)initWithClass:(Class)class
                    initBlock:(ORKESerializationInitBlock)initBlock
                   properties:(NSDictionary *)properties {
    self = [super init];
    if (self) {
        _class = class;
        self.initBlock = initBlock;
        self.properties = [properties mutableCopy];
    }
    return self;
}

@end


@implementation ORKESerializableProperty

- (instancetype)initWithPropertyName:(NSString *)propertyName
                          valueClass:(Class)valueClass
                      containerClass:(Class)containerClass
                      writeAfterInit:(BOOL)writeAfterInit
                   objectToJSONBlock:(ORKESerializationObjectToJSONBlock)objectToJSON
                   jsonToObjectBlock:(ORKESerializationJSONToObjectBlock)jsonToObjectBlock {
    self = [super init];
    if (self) {
        self.propertyName = propertyName;
        self.valueClass = valueClass;
        self.containerClass = containerClass;
        self.writeAfterInit = writeAfterInit;
        self.objectToJSONBlock = objectToJSON;
        self.jsonToObjectBlock = jsonToObjectBlock;
    }
    return self;
}

@end


static NSString *_ClassKey = @"_class";

static id propFromDict(NSDictionary *dict, NSString *propName) {
    NSArray *classEncodings = classEncodingsForClass(NSClassFromString(dict[_ClassKey]));
    ORKESerializableProperty *propertyEntry = nil;
    for (ORKESerializableTableEntry *classEncoding in classEncodings) {
        
        NSDictionary *propertyEncoding = classEncoding.properties;
        propertyEntry = propertyEncoding[propName];
        if (propertyEntry != nil) {
            break;
        }
    }
    NSCAssert(propertyEntry != nil, @"Unexpected property %@ for class %@", propName, dict[_ClassKey]);
    
    Class containerClass = propertyEntry.containerClass;
    Class propertyClass = propertyEntry.valueClass;
    ORKESerializationJSONToObjectBlock converterBlock = propertyEntry.jsonToObjectBlock;
    
    id input = dict[propName];
    id output = nil;
    if (input != nil) {
        if ([containerClass isSubclassOfClass:[NSArray class]]) {
            NSMutableArray *outputArray = [NSMutableArray array];
            for (id value in DYNAMICCAST(input, NSArray)) {
                id convertedValue = objectForJsonObject(value, propertyClass, converterBlock);
                NSCAssert(convertedValue != nil, @"Could not convert to object of class %@", propertyClass);
                [outputArray addObject:convertedValue];
            }
            output = outputArray;
        } else if ([containerClass isSubclassOfClass:[NSDictionary class]]) {
            NSMutableDictionary *outputDictionary = [NSMutableDictionary dictionary];
            for (NSString *key in [DYNAMICCAST(input, NSDictionary) allKeys]) {
                id convertedValue = objectForJsonObject(DYNAMICCAST(input, NSDictionary)[key], propertyClass, converterBlock);
                NSCAssert(convertedValue != nil, @"Could not convert to object of class %@", propertyClass);
                outputDictionary[key] = convertedValue;
            }
        } else {
            NSCAssert(containerClass == [NSObject class], @"Unexpected container class %@", containerClass);
            
            output = objectForJsonObject(input, propertyClass, converterBlock);
        }
    }
    return output;
}


#define NUMTOSTRINGBLOCK(table) ^id(id num) { return table[[num integerValue]]; }
#define STRINGTONUMBLOCK(table) ^id(id string) { NSUInteger index = [table indexOfObject:string]; \
    NSCAssert(index != NSNotFound, @"Expected valid entry from table %@", table); \
    return @(index); \
}

@implementation ORKESerializer

static NSArray *ORKChoiceAnswerStyleTable() {
    static NSArray *table;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = @[@"singleChoice", @"multipleChoice"];
    });
    
    return table;
}

static NSArray *ORKDateAnswerStyleTable() {
    static NSArray *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = @[@"dateTime", @"date"];
    });
    return table;
}

static NSArray *buttonIdentifierTable() {
    static NSArray *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = @[@"none", @"left", @"right"];
    });
    return table;
}

static NSArray *memoryGameStatusTable() {
    static NSArray *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = @[@"unknown", @"success", @"failure", @"timeout"];
    });
    return table;
}

#define GETPROP(d,x) getter(d, @ESTRINGIFY(x))
static NSMutableDictionary *ORKESerializationEncodingTable() {
    static dispatch_once_t onceToken;
    static NSMutableDictionary *ret = nil;
    dispatch_once(&onceToken, ^{
ret =
[@{
  ENTRY(ORKOrderedTask,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            ORKOrderedTask *task = [[ORKOrderedTask alloc] initWithIdentifier:GETPROP(dict, identifier)
                                                                        steps:GETPROP(dict, steps)];
            return task;
        },(@{
          PROPERTY(identifier, NSString, NSObject, NO , nil, nil),
          PROPERTY(steps, ORKStep, NSArray, NO , nil, nil)
          })),
  ENTRY(ORKStep,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            ORKStep *step = [[ORKStep alloc] initWithIdentifier:GETPROP(dict, identifier)];
            return step;
        },
        (@{
          PROPERTY(identifier, NSString, NSObject, NO, nil, nil),
          PROPERTY(optional, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(title, NSString, NSObject, YES, nil, nil),
          PROPERTY(text, NSString, NSObject, YES, nil, nil),
          PROPERTY(shouldTintImages, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(useSurveyMode, NSNumber, NSObject, YES, nil, nil)
          })),
  ENTRY(ORKVisualConsentStep,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKVisualConsentStep alloc] initWithIdentifier:GETPROP(dict, identifier)
                                                           document:GETPROP(dict, consentDocument)];
        },
        @{
          PROPERTY(consentDocument, ORKConsentDocument, NSObject, NO, nil, nil)
          }),
  ENTRY(ORKRecorderConfiguration,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            ORKRecorderConfiguration *recorderConfiguration = [[ORKRecorderConfiguration alloc] initWithIdentifier:GETPROP(dict, identifier)];
            return recorderConfiguration;
        },
        (@{
           PROPERTY(identifier, NSString, NSObject, NO, nil, nil),
          })),
  ENTRY(ORKQuestionStep,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKQuestionStep alloc] initWithIdentifier:GETPROP(dict, identifier)];
        },
        (@{
          PROPERTY(answerFormat, ORKAnswerFormat, NSObject, YES, nil, nil),
          PROPERTY(placeholder, NSString, NSObject, YES, nil, nil)
          })),
  ENTRY(ORKInstructionStep,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKInstructionStep alloc] initWithIdentifier:GETPROP(dict, identifier)];
        },
        (@{
          PROPERTY(detailText, NSString, NSObject, YES, nil, nil),
          })),
  ENTRY(ORKHealthQuantityTypeRecorderConfiguration,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKHealthQuantityTypeRecorderConfiguration alloc] initWithIdentifier:GETPROP(dict, identifier) healthQuantityType:GETPROP(dict, quantityType) unit:GETPROP(dict, unit)];
        },
        (@{
          PROPERTY(quantityType, HKQuantityType, NSObject, NO,
                   ^id(id type) { return [(HKQuantityType *)type identifier]; },
                   ^id(id string) { return [HKQuantityType quantityTypeForIdentifier:string]; }),
          PROPERTY(unit, HKUnit, NSObject, NO,
                   ^id(id unit) { return [(HKUnit *)unit unitString]; },
                   ^id(id string) { return [HKUnit unitFromString:string]; }),
          })),
  ENTRY(ORKActiveStep,
  ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
      return [[ORKActiveStep alloc] initWithIdentifier:GETPROP(dict, identifier)];
  },
  (@{
    PROPERTY(stepDuration, NSNumber, NSObject, YES, nil, nil),
    PROPERTY(shouldShowDefaultTimer, NSNumber, NSObject, YES, nil, nil),
    PROPERTY(shouldSpeakCountDown, NSNumber, NSObject, YES, nil, nil),
    PROPERTY(shouldStartTimerAutomatically, NSNumber, NSObject, YES, nil, nil),
    PROPERTY(shouldPlaySoundOnStart, NSNumber, NSObject, YES, nil, nil),
    PROPERTY(shouldPlaySoundOnFinish, NSNumber, NSObject, YES, nil, nil),
    PROPERTY(shouldVibrateOnStart, NSNumber, NSObject, YES, nil, nil),
    PROPERTY(shouldVibrateOnFinish, NSNumber, NSObject, YES, nil, nil),
    PROPERTY(shouldUseNextAsSkipButton, NSNumber, NSObject, YES, nil, nil),
    PROPERTY(shouldContinueOnFinish, NSNumber, NSObject, YES, nil, nil),
    PROPERTY(spokenInstruction, NSString, NSObject, YES, nil, nil),
    PROPERTY(recorderConfigurations, ORKRecorderConfiguration, NSArray, YES, nil, nil),
    })),
  ENTRY(ORKAudioStep,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKAudioStep alloc] initWithIdentifier:GETPROP(dict, identifier)];
        },
        (@{
          })),
  ENTRY(ORKSpatialSpanMemoryStep,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKSpatialSpanMemoryStep alloc] initWithIdentifier:GETPROP(dict, identifier)];
        },
        (@{
          PROPERTY(initialSpan, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(minimumSpan, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(maximumSpan, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(playSpeed, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(maxTests, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(maxConsecutiveFailures, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(requireReversal, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(customTargetPluralName, NSString, NSObject, YES, nil, nil),
          })),
  ENTRY(ORKWalkingTaskStep,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKWalkingTaskStep alloc] initWithIdentifier:GETPROP(dict, identifier)];
        },
        (@{
          PROPERTY(numberOfStepsPerLeg, NSNumber, NSObject, YES, nil, nil),
          })),
  ENTRY(ORKAccelerometerRecorderConfiguration,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKAccelerometerRecorderConfiguration alloc] initWithIdentifier:GETPROP(dict, identifier) frequency:[GETPROP(dict, frequency) doubleValue]];
        },
        (@{
          PROPERTY(frequency, NSNumber, NSObject, NO, nil, nil),
          })),
  ENTRY(ORKAudioRecorderConfiguration,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKAudioRecorderConfiguration alloc] initWithIdentifier:GETPROP(dict, identifier) recorderSettings:GETPROP(dict, recorderSettings)];
        },
        (@{
          PROPERTY(recorderSettings, NSDictionary, NSObject, NO, nil, nil),
          })),
  ENTRY(ORKConsentDocument,
        nil,
        (@{
          PROPERTY(title, NSString, NSObject, NO, nil, nil),
          PROPERTY(sections, ORKConsentSection, NSArray, NO, nil, nil),
          PROPERTY(signaturePageTitle, NSString, NSObject, NO, nil, nil),
          PROPERTY(signaturePageContent, NSString, NSObject, NO, nil, nil),
          PROPERTY(signatures, ORKConsentSignature, NSArray, NO, nil, nil),
          PROPERTY(htmlReviewContent, NSString, NSObject, NO, nil, nil),
          })),
  ENTRY(ORKConsentSharingStep,
        ^(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKConsentSharingStep alloc] initWithIdentifier:GETPROP(dict, identifier)];
        },
        (@{
           PROPERTY(localizedLearnMoreHTMLContent, NSString, NSObject, YES, nil, nil),
           })),
  ENTRY(ORKConsentReviewStep,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKConsentReviewStep alloc] initWithIdentifier:GETPROP(dict, identifier) signature:GETPROP(dict, signature) inDocument:GETPROP(dict,consentDocument)];
        },
        (@{
          PROPERTY(consentDocument, ORKConsentDocument, NSObject, NO, nil, nil),
          PROPERTY(reasonForConsent, NSString, NSObject, YES, nil, nil),
          PROPERTY(signature, ORKConsentSignature, NSObject, NO, nil, nil),
          })),
  ENTRY(ORKConsentSection,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKConsentSection alloc] initWithType:[GETPROP(dict, type) integerValue]];
        },
        (@{
          PROPERTY(type, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(title, NSString, NSObject, YES, nil, nil),
          PROPERTY(formalTitle, NSString, NSObject, YES, nil, nil),
          PROPERTY(summary, NSString, NSObject, YES, nil, nil),
          PROPERTY(content, NSString, NSObject, YES, nil, nil),
          PROPERTY(htmlContent, NSString, NSObject, YES, nil, nil),
          PROPERTY(customLearnMoreButtonTitle, NSString, NSObject, YES, nil, nil),
          PROPERTY(customAnimationURL, NSURL, NSObject, YES,
                   ^id(id url) { return [(NSURL *)url absoluteString]; },
                   ^id(id string) { return [NSURL URLWithString:string]; }),
          })),
  ENTRY(ORKConsentSignature,
        nil,
        (@{
          PROPERTY(identifier, NSString, NSObject, YES, nil, nil),
          PROPERTY(title, NSString, NSObject, YES, nil, nil),
          PROPERTY(givenName, NSString, NSObject, YES, nil, nil),
          PROPERTY(familyName, NSString, NSObject, YES, nil, nil),
          PROPERTY(signatureDate, NSString, NSObject, YES, nil, nil),
          PROPERTY(requiresName, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(requiresSignatureImage, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(signatureDateFormatString, NSString, NSObject, YES, nil, nil),
          })),
  ENTRY(ORKDeviceMotionRecorderConfiguration,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKDeviceMotionRecorderConfiguration alloc] initWithIdentifier:GETPROP(dict, identifier) frequency:[GETPROP(dict, frequency) doubleValue]];
        },
        (@{
          PROPERTY(frequency, NSNumber, NSObject, NO, nil, nil),
          })),
  ENTRY(ORKFormStep,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKFormStep alloc] initWithIdentifier:GETPROP(dict, identifier)];
        },
        (@{
          PROPERTY(formItems, ORKFormItem, NSArray, YES, nil, nil)
          })),
  ENTRY(ORKFormItem,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKFormItem alloc] initWithIdentifier:GETPROP(dict, identifier) text:GETPROP(dict, text) answerFormat:GETPROP(dict, answerFormat)];
        },
        (@{
          PROPERTY(identifier, NSString, NSObject, NO, nil, nil),
          PROPERTY(text, NSString, NSObject, NO, nil, nil),
          PROPERTY(placeholder, NSString, NSObject, YES, nil, nil),
          PROPERTY(answerFormat, ORKAnswerFormat, NSObject, NO, nil, nil),
          })),
  ENTRY(ORKHealthKitCharacteristicTypeAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKHealthKitCharacteristicTypeAnswerFormat alloc] initWithCharacteristicType:GETPROP(dict, characteristicType)];
        },
        (@{
          PROPERTY(characteristicType, HKCharacteristicType, NSObject, NO,
                   ^id(id type) { return [(HKCharacteristicType *)type identifier]; },
                   ^id(id string) { return [HKCharacteristicType characteristicTypeForIdentifier:string]; }),
          })),
  ENTRY(ORKHealthKitQuantityTypeAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKHealthKitQuantityTypeAnswerFormat alloc] initWithQuantityType:GETPROP(dict, quantityType) unit:GETPROP(dict, unit) style:[GETPROP(dict, numericAnswerStyle) integerValue]];
        },
        (@{
          PROPERTY(unit, HKUnit, NSObject, NO,
                   ^id(id unit) { return [(HKUnit *)unit unitString]; },
                   ^id(id string) { return [HKUnit unitFromString:string]; }),
          PROPERTY(quantityType, HKQuantityType, NSObject, NO,
                   ^id(id type) { return [(HKQuantityType *)type identifier]; },
                   ^id(id string) { return [HKQuantityType quantityTypeForIdentifier:string]; }),
          PROPERTY(numericAnswerStyle, NSNumber, NSObject, NO,
                   ^id(id num) { return ORKNumericAnswerStyleToString([num integerValue]); },
                   ^id(id string) { return @(ORKNumericAnswerStyleFromString(string)); }),
          })),
  ENTRY(ORKAnswerFormat,
        nil,
        (@{
          })),
  ENTRY(ORKValuePickerAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKValuePickerAnswerFormat alloc] initWithTextChoices:GETPROP(dict, textChoices)];
        },
        (@{
          PROPERTY(textChoices, ORKTextChoice, NSArray, NO, nil, nil),
          
          })),
  ENTRY(ORKImageChoiceAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKImageChoiceAnswerFormat alloc] initWithImageChoices:GETPROP(dict, imageChoices)];
        },
        (@{
          PROPERTY(imageChoices, ORKImageChoice, NSArray, NO, nil, nil),
          })),
  ENTRY(ORKTextChoiceAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKTextChoiceAnswerFormat alloc] initWithStyle:[GETPROP(dict, style) integerValue] textChoices:GETPROP(dict, textChoices)];
        },
        (@{
          PROPERTY(style, NSNumber, NSObject, NO, NUMTOSTRINGBLOCK(ORKChoiceAnswerStyleTable()), STRINGTONUMBLOCK(ORKChoiceAnswerStyleTable())),
          PROPERTY(textChoices, ORKTextChoice, NSArray, NO, nil, nil),
          })),
  ENTRY(ORKTextChoice,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKTextChoice alloc] initWithText:GETPROP(dict, text) detailText:GETPROP(dict, detailText) value:GETPROP(dict, value)];
        },
        (@{
          PROPERTY(text, NSString, NSObject, NO, nil, nil),
          PROPERTY(value, NSObject, NSObject, NO, nil, nil),
          PROPERTY(detailText, NSString, NSObject, NO, nil, nil),
          })),
  ENTRY(ORKImageChoice,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKImageChoice alloc] initWithNormalImage:nil selectedImage:nil text:GETPROP(dict, text) value:GETPROP(dict, value)];
        },
        (@{
          PROPERTY(text, NSString, NSObject, NO, nil, nil),
          PROPERTY(value, NSObject, NSObject, NO, nil, nil),
          })),
  ENTRY(ORKTimeOfDayAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKTimeOfDayAnswerFormat alloc] initWithDefaultComponents:GETPROP(dict, defaultComponents)];
        },
        (@{
          PROPERTY(defaultComponents, NSDateComponents, NSObject, NO,
                   ^id(id components) { return ORKTimeOfDayStringFromComponents(components);  },
                   ^id(id string) { return ORKTimeOfDayComponentsFromString(string); })
          })),
  ENTRY(ORKDateAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKDateAnswerFormat alloc] initWithStyle:[GETPROP(dict, style) integerValue] defaultDate:GETPROP(dict, defaultDate) minimumDate:GETPROP(dict, minimumDate) maximumDate:GETPROP(dict, maximumDate) calendar:GETPROP(dict, calendar)];
        },
        (@{
          PROPERTY(style, NSNumber, NSObject, NO,
                   NUMTOSTRINGBLOCK(ORKDateAnswerStyleTable()),
                   STRINGTONUMBLOCK(ORKDateAnswerStyleTable())),
          PROPERTY(calendar, NSCalendar, NSObject, NO,
                   ^id(id calendar) { return [(NSCalendar *)calendar calendarIdentifier]; },
                   ^id(id string) { return [NSCalendar calendarWithIdentifier:string]; }),
          PROPERTY(minimumDate, NSDate, NSObject, NO,
                   ^id(id date) { return [ORKResultDateTimeFormatter() stringFromDate:date]; },
                   ^id(id string) { return [ORKResultDateTimeFormatter() dateFromString:string]; }),
          PROPERTY(maximumDate, NSDate, NSObject, NO,
                   ^id(id date) { return [ORKResultDateTimeFormatter() stringFromDate:date]; },
                   ^id(id string) { return [ORKResultDateTimeFormatter() dateFromString:string]; }),
          PROPERTY(defaultDate, NSDate, NSObject, NO,
                   ^id(id date) { return [ORKResultDateTimeFormatter() stringFromDate:date]; },
                   ^id(id string) { return [ORKResultDateTimeFormatter() dateFromString:string]; }),
          
          })),
  ENTRY(ORKNumericAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKNumericAnswerFormat alloc] initWithStyle:[GETPROP(dict, style) integerValue] unit:GETPROP(dict, unit) minimum:GETPROP(dict, minimum) maximum:GETPROP(dict, maximum)];
        },
        (@{
          PROPERTY(style, NSNumber, NSObject, NO,
                   ^id(id num) { return ORKNumericAnswerStyleToString([num integerValue]); },
                   ^id(id string) { return @(ORKNumericAnswerStyleFromString(string)); }),
          PROPERTY(unit, NSString, NSObject, NO, nil, nil),
          PROPERTY(minimum, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(maximum, NSNumber, NSObject, NO, nil, nil),
          })),
  ENTRY(ORKScaleAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKScaleAnswerFormat alloc] initWithMaximumValue:[GETPROP(dict, maximum) integerValue] minimumValue:[GETPROP(dict, minimum) integerValue] defaultValue:[GETPROP(dict, defaultValue) integerValue] step:[GETPROP(dict, step) integerValue] vertical:[GETPROP(dict, vertical) boolValue]];
        },
        (@{
          PROPERTY(minimum, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(maximum, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(defaultValue, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(step, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(vertical, NSNumber, NSObject, NO, nil, nil)
          })),
  ENTRY(ORKContinuousScaleAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKContinuousScaleAnswerFormat alloc] initWithMaximumValue:[GETPROP(dict, maximum) doubleValue] minimumValue:[GETPROP(dict, minimum) doubleValue] defaultValue:[GETPROP(dict, defaultValue) doubleValue] maximumFractionDigits:[GETPROP(dict, maximumFractionDigits) integerValue] vertical:[GETPROP(dict, vertical) boolValue]];
        },
        (@{
          PROPERTY(minimum, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(maximum, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(defaultValue, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(maximumFractionDigits, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(vertical, NSNumber, NSObject, NO, nil, nil)
          })),
  ENTRY(ORKTextAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKTextAnswerFormat alloc] initWithMaximumLength:[GETPROP(dict, maximumLength) integerValue]];
        },
        (@{
          PROPERTY(maximumLength, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(autocapitalizationType, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(autocorrectionType, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(spellCheckingType, NSNumber, NSObject, YES, nil, nil),
          PROPERTY(multipleLines, NSNumber, NSObject, YES, nil, nil),
          })),
  ENTRY(ORKTimeIntervalAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKTimeIntervalAnswerFormat alloc] initWithDefaultInterval:[GETPROP(dict, defaultInterval) doubleValue] step:[GETPROP(dict, step) integerValue]];
        },
        (@{
          PROPERTY(defaultInterval, NSNumber, NSObject, NO, nil, nil),
          PROPERTY(step, NSNumber, NSObject, NO, nil, nil),
          })),
  ENTRY(ORKBooleanAnswerFormat,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            return [[ORKBooleanAnswerFormat alloc] init];
        },
        (@{
          })),
  ENTRY(ORKLocationRecorderConfiguration,
        nil,
        (@{
          })),
  ENTRY(ORKPedometerRecorderConfiguration,
        nil,
        (@{
          })),
  ENTRY(ORKTouchRecorderConfiguration,
        nil,
        (@{
          })),
  ENTRY(ORKResult,
        nil,
        (@{
           PROPERTY(identifier, NSString, NSObject, NO, nil, nil),
           PROPERTY(startDate, NSDate, NSObject, YES,
                    ^id(id date) { return ORKEStringFromDateISO8601(date); },
                    ^id(id string) { return ORKEDateFromStringISO8601(string); }),
           PROPERTY(endDate, NSDate, NSObject, YES,
                    ^id(id date) { return ORKEStringFromDateISO8601(date); },
                    ^id(id string) { return ORKEDateFromStringISO8601(string); }),
           PROPERTY(userInfo, NSDictionary, NSObject, YES, nil, nil)
           })),
  ENTRY(ORKTappingSample,
        nil,
        (@{
           PROPERTY(timestamp, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(buttonIdentifier, NSNumber, NSObject, NO,
                    ^id(id numeric) { return tableMapForward([numeric integerValue], buttonIdentifierTable()); },
                    ^id(id string) { return @(tableMapReverse(string, buttonIdentifierTable())); }),
           PROPERTY(location, NSValue, NSObject, NO,
                    ^id(id value) { return value?dictionaryFromCGPoint([value CGPointValue]):nil; },
                    ^id(id dict) { return [NSValue valueWithCGPoint:pointFromDictionary(dict)]; })
           })),
  ENTRY(ORKTappingIntervalResult,
        nil,
        (@{
           PROPERTY(samples, ORKTappingSample, NSArray, NO, nil, nil),
           PROPERTY(stepViewSize, NSValue, NSObject, NO,
                    ^id(id value) { return value?dictionaryFromCGSize([value CGSizeValue]):nil; },
                    ^id(id dict) { return [NSValue valueWithCGSize:sizeFromDictionary(dict)]; }),
           PROPERTY(buttonRect1, NSValue, NSObject, NO,
                    ^id(id value) { return value?dictionaryFromCGRect([value CGRectValue]):nil; },
                    ^id(id dict) { return [NSValue valueWithCGRect:rectFromDictionary(dict)]; }),
           PROPERTY(buttonRect2, NSValue, NSObject, NO,
                    ^id(id value) { return value?dictionaryFromCGRect([value CGRectValue]):nil; },
                    ^id(id dict) { return [NSValue valueWithCGRect:rectFromDictionary(dict)]; })
           })),
  ENTRY(ORKSpatialSpanMemoryGameTouchSample,
        nil,
        (@{
           PROPERTY(timestamp, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(targetIndex, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(correct, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(location, NSValue, NSObject, NO,
                    ^id(id value) { return value?dictionaryFromCGPoint([value CGPointValue]):nil; },
                    ^id(id dict) { return [NSValue valueWithCGPoint:pointFromDictionary(dict)]; })
           })),
  ENTRY(ORKSpatialSpanMemoryGameRecord,
        nil,
        (@{
           PROPERTY(seed, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(sequence, NSNumber, NSArray, NO, nil, nil),
           PROPERTY(gameSize, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(gameStatus, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(score, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(touchSamples, ORKSpatialSpanMemoryGameTouchSample, NSArray, NO,
                    ^id(id numeric) { return tableMapForward([numeric integerValue], memoryGameStatusTable()); },
                    ^id(id string) { return @(tableMapReverse(string, memoryGameStatusTable())); }),
           PROPERTY(targetRects, NSValue, NSArray, NO,
                    ^id(id value) { return value?dictionaryFromCGRect([value CGRectValue]):nil; },
                    ^id(id dict) { return [NSValue valueWithCGRect:rectFromDictionary(dict)]; })
           })),
  ENTRY(ORKSpatialSpanMemoryResult,
        nil,
        (@{
           PROPERTY(score, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(numberOfGames, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(numberOfFailures, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(gameRecords, ORKSpatialSpanMemoryGameRecord, NSArray, NO, nil, nil)
           })),
  ENTRY(ORKFileResult,
        nil,
        (@{
           PROPERTY(contentType, NSString, NSObject, NO, nil, nil),
           PROPERTY(fileURL, NSURL, NSObject, NO,
                    ^id(id url) { return [url absoluteString]; },
                    ^id(id string) { return [NSURL URLWithString:string]; })
           })),
  ENTRY(ORKQuestionResult,
        nil,
        (@{
           PROPERTY(questionType, NSNumber, NSObject, NO, nil, nil)
           })),
  ENTRY(ORKScaleQuestionResult,
        nil,
        (@{
           PROPERTY(scaleAnswer, NSNumber, NSObject, NO, nil, nil)
           })),
  ENTRY(ORKChoiceQuestionResult,
        nil,
        (@{
           PROPERTY(choiceAnswers, NSObject, NSObject, NO, nil, nil)
           })),
  ENTRY(ORKBooleanQuestionResult,
        nil,
        (@{
           PROPERTY(booleanAnswer, NSNumber, NSObject, NO, nil, nil)
           })),
  ENTRY(ORKTextQuestionResult,
        nil,
        (@{
           PROPERTY(textAnswer, NSString, NSObject, NO, nil, nil)
           })),
  ENTRY(ORKNumericQuestionResult,
        nil,
        (@{
           PROPERTY(numericAnswer, NSNumber, NSObject, NO, nil, nil),
           PROPERTY(unit, NSString, NSObject, NO, nil, nil)
           })),
  ENTRY(ORKTimeOfDayQuestionResult,
        nil,
        (@{
           PROPERTY(dateComponentsAnswer, NSDateComponents, NSObject, NO,
                    ^id(id dateComponents) { return ORKTimeOfDayStringFromComponents(dateComponents); },
                    ^id(id string) { return ORKTimeOfDayComponentsFromString(string); })
           })),
  ENTRY(ORKTimeIntervalQuestionResult,
        nil,
        (@{
           PROPERTY(intervalAnswer, NSNumber, NSObject, NO, nil, nil)
           })),
  ENTRY(ORKDateQuestionResult,
        nil,
        (@{
           PROPERTY(dateAnswer, NSDate, NSObject, NO,
                    ^id(id date) { return ORKEStringFromDateISO8601(date); },
                    ^id(id string) { return ORKEDateFromStringISO8601(string); }),
           PROPERTY(calendar, NSCalendar, NSObject, NO,
                    ^id(id calendar) { return [(NSCalendar *)calendar calendarIdentifier]; },
                    ^id(id string) { return [NSCalendar calendarWithIdentifier:string]; }),
           PROPERTY(timeZone, NSTimeZone, NSObject, NO,
                    ^id(id timezone) { return @([timezone secondsFromGMT]); },
                    ^id(id number) { return [NSTimeZone timeZoneForSecondsFromGMT:[number doubleValue]]; })
           })),
  ENTRY(ORKConsentSignatureResult,
        nil,
        (@{
           PROPERTY(signature, ORKConsentSignature, NSObject, NO, nil, nil)
           })),
  ENTRY(ORKCollectionResult,
        nil,
        (@{
           PROPERTY(results, ORKResult, NSArray, YES, nil, nil)
           })),
  ENTRY(ORKTaskResult,
        ^id(NSDictionary *dict, ORKESerializationPropertyGetter getter) {
            NSLog(@"blah");
            return [[ORKTaskResult alloc] initWithTaskIdentifier:GETPROP(dict, identifier) taskRunUUID:GETPROP(dict, taskRunUUID) outputDirectory:GETPROP(dict, outputDirectory)];
        },
        (@{
           PROPERTY(taskRunUUID, NSUUID, NSObject, NO,
                    ^id(id uuid) { return [uuid UUIDString]; },
                    ^id(id string) { return [[NSUUID alloc] initWithUUIDString:string]; }),
           PROPERTY(outputDirectory, NSURL, NSObject, NO,
                    ^id(id url) { return [url absoluteString]; },
                    ^id(id string) { return [NSURL URLWithString:string]; })
           })),
  ENTRY(ORKStepResult,
        nil,
        (@{
           })),
  
  } mutableCopy];
    });
    return ret;
}
#undef GETPROP

static NSArray *classEncodingsForClass(Class c) {
    NSDictionary *encodingTable = ORKESerializationEncodingTable();
    
    NSMutableArray *classEncodings = [NSMutableArray array];
    Class sc = c;
    while (sc != nil) {
        NSString *className = NSStringFromClass(sc);
        ORKESerializableTableEntry *classEncoding = encodingTable[className];
        if (classEncoding) {
            [classEncodings addObject:classEncoding];
        }
        sc = [sc superclass];
    }
    return classEncodings;
}

static id objectForJsonObject(id input, Class expectedClass, ORKESerializationJSONToObjectBlock converterBlock) {
    id output = nil;
    if (converterBlock != nil) {
        input = converterBlock(input);
    }
    
    if (expectedClass != nil && [input isKindOfClass:expectedClass]) {
        // Input is already of the expected class, do nothing
        output = input;
    } else if ([input isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)input;
        NSString *className = input[_ClassKey];
        if (expectedClass != nil) {
            NSCAssert([NSClassFromString(className) isSubclassOfClass:expectedClass], @"Expected subclass of %@ but got %@", expectedClass, className);
        }
        NSArray *classEncodings = classEncodingsForClass(NSClassFromString(className));
        NSCAssert([classEncodings count] > 0, @"Expected serializable class but got %@", className);
        
        ORKESerializableTableEntry *leafClassEncoding = [classEncodings firstObject];
        ORKESerializationInitBlock initBlock = leafClassEncoding.initBlock;
        BOOL writeAllProperties = YES;
        if (initBlock != nil) {
            output = initBlock(dict,
                               ^id(NSDictionary *dict, NSString *param) {
                                   return propFromDict(dict, param); });
            writeAllProperties = NO;
        } else {
            output = [[NSClassFromString(className) alloc] init];
        }
        
        for (NSString *key in [dict allKeys]) {
            if ([key isEqualToString:_ClassKey]) {
                continue;
            }
            
            BOOL haveSetProp = NO;
            for (ORKESerializableTableEntry *encoding in classEncodings) {
                NSDictionary *propertyTable = encoding.properties;
                ORKESerializableProperty *propertyEntry = propertyTable[key];
                if (propertyEntry != nil) {
                    // Only write the property if it has not already been set during init
                    if (writeAllProperties || propertyEntry.writeAfterInit) {
                        [output setValue:propFromDict(dict,key) forKey:key];
                    }
                    haveSetProp = YES;
                    break;
                }
            }
            NSCAssert(haveSetProp, @"Unexpected property on %@: %@", className, key);
        }
        
    } else {
        NSCAssert(0, @"Unexpected input of class %@ for %@", [input class], expectedClass);
    }
    return output;
}

static BOOL isValid(id object) {
    return [NSJSONSerialization isValidJSONObject:object] || [object isKindOfClass:[NSNumber class]] || [object isKindOfClass:[NSString class]] || [object isKindOfClass:[NSNull class]];
}

static id jsonObjectForObject(id object) {
    if (object == nil) {
        // Leaf: nil
        return nil;
    }
    
    id jsonOutput = nil;
    Class c = [object class];
    
    NSArray *classEncodings = classEncodingsForClass(c);
    
    if ([classEncodings count]) {
        NSMutableDictionary *encodedDict = [NSMutableDictionary dictionary];
        encodedDict[_ClassKey] = NSStringFromClass(c);
        
        for (ORKESerializableTableEntry *encoding in classEncodings) {
            NSDictionary *propertyTable = encoding.properties;
            for (NSString *propertyName in [propertyTable allKeys]) {
                ORKESerializableProperty *propertyEntry = propertyTable[propertyName];
                ORKESerializationObjectToJSONBlock converter = propertyEntry.objectToJSONBlock;
                Class containerClass = propertyEntry.containerClass;
                id valueForKey = [object valueForKey:propertyName];
                if (valueForKey != nil) {
                    if ([containerClass isSubclassOfClass:[NSArray class]]) {
                        NSMutableArray *a = [NSMutableArray array];
                        for (id valueItem in valueForKey) {
                            id outputItem;
                            if (converter != nil) {
                                outputItem = converter(valueItem);
                                NSCAssert(isValid(valueItem), @"Expected valid JSON object");
                            } else {
                                // Recurse for each property
                                outputItem = jsonObjectForObject(valueItem);
                            }
                            [a addObject:outputItem];
                        }
                        valueForKey = a;
                    } else {
                        if (converter != nil) {
                            valueForKey = converter(valueForKey);
                            NSCAssert((valueForKey == nil) || isValid(valueForKey), @"Expected valid JSON object");
                        } else {
                            // Recurse for each property
                            valueForKey = jsonObjectForObject(valueForKey);
                        }
                    }
                }
                
                if (valueForKey != nil) {
                    encodedDict[propertyName] = valueForKey;
                }
            }
        }
        
        jsonOutput = encodedDict;
    } else if ([c isSubclassOfClass:[NSArray class]]) {
        NSArray *inputArray = (NSArray *)object;
        NSMutableArray *encodedArray = [NSMutableArray arrayWithCapacity:[inputArray count]];
        for (id input in inputArray) {
            // Recurse for each array element
            [encodedArray addObject:jsonObjectForObject(input)];
        }
        jsonOutput = encodedArray;
    } else if ([c isSubclassOfClass:[NSDictionary class]]) {
        NSDictionary *inputDict = (NSDictionary *)object;
        NSMutableDictionary *encodedDictionary = [NSMutableDictionary dictionaryWithCapacity:[inputDict count]];
        for (NSString *key in [inputDict allKeys] ) {
            // Recurse for each dictionary value
            encodedDictionary[key] = jsonObjectForObject(inputDict[key]);
        }
        jsonOutput = encodedDictionary;
    } else {
        NSCAssert(isValid(object), @"Expected valid JSON object");
        
        // Leaf: native JSON object
        jsonOutput = object;
    }
    
    return jsonOutput;
}

+ (NSDictionary *)JSONObjectForObject:(id)object error:(NSError * __autoreleasing *)error {
    id json = jsonObjectForObject(object);
    return json;
}

+ (id)objectFromJSONObject:(NSDictionary *)object error:(NSError *__autoreleasing *)error {
    return objectForJsonObject(object, nil, nil);
}

+ (NSData *)JSONDataForObject:(id)object error:(NSError *__autoreleasing *)error {
    id json = jsonObjectForObject(object);
    return [NSJSONSerialization dataWithJSONObject:json options:(NSJSONWritingOptions)0 error:error];
}

+ (id)objectFromJSONData:(NSData *)data error:(NSError *__autoreleasing *)error {
    id json = [NSJSONSerialization JSONObjectWithData:data options:(NSJSONReadingOptions)0 error:error];
    id ret = nil;
    if (json != nil) {
        ret = objectForJsonObject(json, nil, nil);
    }
    return ret;
}

+ (NSArray *)serializableClasses {
    NSMutableArray *a = [NSMutableArray array];
    NSDictionary *table = ORKESerializationEncodingTable();
    for (NSString *key in [table allKeys]) {
        [a addObject:NSClassFromString(key)];
    }
    return a;
}

@end


@implementation ORKESerializer(Registration)

+ (void)registerSerializableClass:(Class)serializableClass
                        initBlock:(ORKESerializationInitBlock)initBlock {
    NSMutableDictionary *encodingTable = ORKESerializationEncodingTable();
    
    ORKESerializableTableEntry *entry = encodingTable[NSStringFromClass(serializableClass)];
    if (entry) {
        entry.class = serializableClass;
        entry.initBlock = initBlock;
    } else {
        entry = [[ORKESerializableTableEntry alloc] initWithClass:serializableClass initBlock:initBlock properties:@{}];
        encodingTable[NSStringFromClass(serializableClass)] = entry;
    }
}

+ (void)registerSerializableClassPropertyName:(NSString *)propertyName
                                     forClass:(Class)serializableClass
                                   valueClass:(Class)valueClass
                               containerClass:(Class)containerClass
                               writeAfterInit:(BOOL)writeAfterInit
                            objectToJSONBlock:(ORKESerializationObjectToJSONBlock)objectToJSON
                            jsonToObjectBlock:(ORKESerializationJSONToObjectBlock)jsonToObjectBlock {
    NSMutableDictionary *encodingTable = ORKESerializationEncodingTable();
    
    ORKESerializableTableEntry *entry = encodingTable[NSStringFromClass(serializableClass)];
    if (! entry) {
        entry = [[ORKESerializableTableEntry alloc] initWithClass:serializableClass initBlock:nil properties:@{}];
        encodingTable[NSStringFromClass(serializableClass)] = entry;
    }
    
    ORKESerializableProperty *property = entry.properties[propertyName];
    if (property == nil) {
        property = [[ORKESerializableProperty alloc] initWithPropertyName:propertyName
                                                               valueClass:valueClass
                                                           containerClass:containerClass
                                                           writeAfterInit:writeAfterInit
                                                        objectToJSONBlock:objectToJSON
                                                        jsonToObjectBlock:jsonToObjectBlock];
        entry.properties[propertyName] = property;
    } else {
        property.propertyName = propertyName;
        property.valueClass = valueClass;
        property.containerClass = containerClass;
        property.writeAfterInit = writeAfterInit;
        property.objectToJSONBlock = objectToJSON;
        property.jsonToObjectBlock = jsonToObjectBlock;
    }
}

@end
