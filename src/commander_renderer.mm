#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include "commander_renderer.h"

#ifndef __has_feature
  #define __has_feature(x) 0
#endif

#if !__has_feature(objc_arc)
#error "Build commander renderer with -fobjc-arc"
#endif

@class CommanderRuntime;
@class CommanderPanel;
@class CommanderTableView;
@class CommanderRowView;
@class CommanderCellView;
@class CommanderRowsOverlayView;
@class CommanderAppDelegate;

static NSColor *mc_blue(void);
static NSColor *mc_blue_dark(void);
static NSColor *mc_cyan(void);
static NSColor *mc_header_dark(void);
static NSColor *mc_line(void);
static NSColor *mc_white(void);
static NSColor *mc_yellow(void);
static NSColor *mc_green(void);
static NSTextField *mc_label(NSRect frame, NSString *text, NSColor *textColor, NSFont *font, NSTextAlignment alignment);
static NSString *str_from_c(const char *text);

@interface CommanderRuntime : NSObject
@property (nonatomic, assign) NSInteger panelCount;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, assign) NSInteger activePanel;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL shown;
@property (nonatomic, assign) BOOL allowClose;
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) CommanderAppDelegate *appDelegate;
@property (nonatomic, strong) NSMutableArray<CommanderPanel *> *panels;
@property (nonatomic, strong) NSMutableArray<NSValue *> *eventQueue;
@property (nonatomic, strong) NSTextField *statusLabel;
- (instancetype)initWithPanelCount:(NSInteger)panelCount width:(CGFloat)width height:(CGFloat)height;
- (void)pushEvent:(commander_render_event_t)event;
- (BOOL)popEvent:(commander_render_event_t *)outEvent;
- (void)focusPanel:(NSInteger)index;
- (void)focusNextPanel;
- (void)requestStop;
@end

@interface CommanderAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (nonatomic, weak) CommanderRuntime *runtime;
- (instancetype)initWithRuntime:(CommanderRuntime *)runtime;
- (void)requestQuit:(id)sender;
@end

@interface CommanderTableView : NSTableView
@property (nonatomic, weak) CommanderPanel *panel;
@end

@interface CommanderRowView : NSTableRowView
@end

@interface CommanderCellView : NSView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSColor *textColor;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic, assign) NSTextAlignment alignment;
@end

@interface CommanderRowsOverlayView : NSView
@property (nonatomic, weak) CommanderPanel *panel;
@end

@interface CommanderPanel : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, weak) CommanderRuntime *runtime;
@property (nonatomic, assign) NSInteger cursor;
@property (nonatomic, assign) BOOL updatingCursor;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *items;
@property (nonatomic, strong) NSView *rootView;
@property (nonatomic, strong) NSTextField *header;
@property (nonatomic, strong) NSTextField *pathLabel;
@property (nonatomic, strong) CommanderTableView *table;
@property (nonatomic, strong) CommanderRowsOverlayView *rowsOverlay;
@property (nonatomic, strong) NSTextField *hintLabel;
- (instancetype)initWithIndex:(NSInteger)index runtime:(CommanderRuntime *)runtime;
- (void)setActive:(BOOL)active;
- (void)setPathText:(NSString *)text;
- (void)setRows:(const commander_render_row_t *)rows count:(NSInteger)count cursor:(NSInteger)cursor;
- (void)applyCursor:(NSInteger)cursor;
- (NSInteger)selectedRowIndex;
- (void)refreshFooter;
- (void)emitKeyEvent:(NSEvent *)event;
- (void)emitSyntheticKeyCode:(int32_t)keyCode modifiers:(uint32_t)modifiers;
- (void)emitTabEvent:(NSEvent *)event;
- (void)emitQuitEvent:(NSEvent *)event;
- (void)emitMouseDownEvent:(NSEvent *)event row:(NSInteger)row;
- (void)emitRowSelectedEvent:(NSInteger)row;
- (void)emitRowActivatedEvent:(NSEvent *)event row:(NSInteger)row;
- (void)drawRowsInTableView:(NSTableView *)tableView dirtyRect:(NSRect)dirtyRect;
- (void)drawRowsInOverlayView:(NSView *)overlay dirtyRect:(NSRect)dirtyRect;
@end

static CommanderPanel *build_panel(NSView *parent, CGFloat x, CGFloat y, CGFloat w, CGFloat h, NSInteger index, CommanderRuntime *runtime);
static void build_window_if_needed(CommanderRuntime *runtime);
static CommanderRuntime *runtime_from_handle(void *handle);

@implementation CommanderRuntime

- (instancetype)initWithPanelCount:(NSInteger)panelCount width:(CGFloat)width height:(CGFloat)height
{
    self = [super init];
    if (self) {
        _panelCount = panelCount < 1 ? 1 : (panelCount > 8 ? 8 : panelCount);
        _width = width < 900.0 ? 1360.0 : width;
        _height = height < 520.0 ? 860.0 : height;
        _activePanel = 0;
        _running = NO;
        _shown = NO;
        _allowClose = NO;
        _panels = [NSMutableArray arrayWithCapacity:_panelCount];
        _eventQueue = [NSMutableArray array];
    }
    return self;
}

- (void)pushEvent:(commander_render_event_t)event
{
    @synchronized (self.eventQueue) {
        [self.eventQueue addObject:[NSValue valueWithBytes:&event objCType:@encode(commander_render_event_t)]];
    }
}

- (BOOL)popEvent:(commander_render_event_t *)outEvent
{
    if (!outEvent) {
        return NO;
    }

    @synchronized (self.eventQueue) {
        if (self.eventQueue.count == 0) {
            return NO;
        }
        NSValue *value = self.eventQueue.firstObject;
        [self.eventQueue removeObjectAtIndex:0];
        [value getValue:outEvent];
    }
    return YES;
}

- (void)focusPanel:(NSInteger)index
{
    if (self.panels.count == 0) {
        return;
    }

    if (index < 0) {
        index = (NSInteger)self.panels.count - 1;
    } else if (index >= (NSInteger)self.panels.count) {
        index = 0;
    }

    self.activePanel = index;
    for (NSInteger i = 0; i < (NSInteger)self.panels.count; i++) {
        [self.panels[i] setActive:(i == index)];
    }

    CommanderPanel *active = self.panels[index];
    if (self.window) {
        [self.window makeFirstResponder:active.table];
    }
}

- (void)focusNextPanel
{
    [self focusPanel:self.activePanel + 1];
}

- (void)requestStop
{
    self.running = NO;
    if (self.window) {
        self.allowClose = YES;
        [self.window close];
    }
}

@end

@implementation CommanderAppDelegate

- (instancetype)initWithRuntime:(CommanderRuntime *)runtime
{
    self = [super init];
    if (self) {
        _runtime = runtime;
    }
    return self;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return NO;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    if (self.runtime) {
        commander_render_event_t event = {};
        event.type = COMMANDER_EVENT_QUIT;
        event.panel = (int32_t)self.runtime.activePanel;
        [self.runtime pushEvent:event];
        self.runtime.running = NO;
    }
    return NSTerminateCancel;
}

- (void)requestQuit:(id)sender
{
    if (!self.runtime) {
        return;
    }
    commander_render_event_t event = {};
    event.type = COMMANDER_EVENT_QUIT;
    event.panel = (int32_t)self.runtime.activePanel;
    [self.runtime pushEvent:event];
}

- (BOOL)windowShouldClose:(NSWindow *)sender
{
    if (!self.runtime) {
        return YES;
    }

    commander_render_event_t event = {};
    event.type = COMMANDER_EVENT_WINDOW_CLOSE;
    event.panel = (int32_t)self.runtime.activePanel;
    [self.runtime pushEvent:event];

    if (self.runtime.allowClose) {
        return YES;
    }
    return NO;
}

- (void)windowWillClose:(NSNotification *)notification
{
    if (self.runtime) {
        self.runtime.running = NO;
    }
}

@end

@implementation CommanderTableView

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    [self.panel drawRowsInTableView:self dirtyRect:dirtyRect];
}

- (void)keyDown:(NSEvent *)event
{
    if (!self.panel) {
        [super keyDown:event];
        return;
    }

    [self.panel emitKeyEvent:event];

    NSInteger keyCode = event.keyCode;
    NSEventModifierFlags modifiers = event.modifierFlags;

    if (keyCode == 48) { // Tab
        [self.panel.runtime focusNextPanel];
        [self.panel emitTabEvent:event];
        return;
    }

    if (keyCode == 36 || keyCode == 76) { // Enter/Return
        [self.panel emitRowActivatedEvent:event row:[self.panel selectedRowIndex]];
        return;
    }

    if (keyCode == 12 && (modifiers & (NSEventModifierFlagControl | NSEventModifierFlagCommand))) { // q
        [self.panel emitQuitEvent:event];
        return;
    }

    if (keyCode == 51) { // Backspace/Delete key event is emitted, Crystal handles behavior.
        return;
    }

    if (keyCode == 126 || keyCode == 125 || keyCode == 115 || keyCode == 119 || keyCode == 116 || keyCode == 121) { // Navigation keys: emit KEY, let Crystal drive cursor/scroll.
        return;
    }

    [super keyDown:event];
}

- (void)mouseDown:(NSEvent *)event
{
    if (!self.panel) {
        [super mouseDown:event];
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:point];
    [self.panel emitMouseDownEvent:event row:row];
    [self.panel.runtime focusPanel:self.panel.index];
    [super mouseDown:event];

    if (event.clickCount >= 2) {
        [self.panel emitRowActivatedEvent:event row:[self.panel selectedRowIndex]];
    }
}

- (void)scrollWheel:(NSEvent *)event
{
    if (!self.panel) {
        [super scrollWheel:event];
        return;
    }

    CGFloat deltaY = event.scrollingDeltaY;
    if (deltaY == 0.0) {
        return;
    }

    NSInteger steps = (NSInteger)ceil(fabs(deltaY) / 8.0);
    if (steps < 1) {
        steps = 1;
    } else if (steps > 6) {
        steps = 6;
    }

    int32_t keyCode = deltaY > 0.0 ? 125 : 126; // Trackpad natural scroll: positive delta moves selection down.
    [self.panel.runtime focusPanel:self.panel.index];
    for (NSInteger i = 0; i < steps; i++) {
        [self.panel emitSyntheticKeyCode:keyCode modifiers:(uint32_t)event.modifierFlags];
    }
}

@end

@implementation CommanderRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
    [mc_cyan() setFill];
    NSRectFill(dirtyRect);
}

@end

@implementation CommanderCellView

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _text = @"";
        _textColor = mc_white();
        _font = [NSFont fontWithName:@"Menlo" size:13] ?: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
        _alignment = NSTextAlignmentLeft;
        self.wantsLayer = NO;
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)setText:(NSString *)text
{
    _text = [text copy] ?: @"";
    [self setNeedsDisplay:YES];
}

- (void)setTextColor:(NSColor *)textColor
{
    _textColor = textColor ?: mc_white();
    [self setNeedsDisplay:YES];
}

- (void)setFont:(NSFont *)font
{
    _font = font ?: ([NSFont fontWithName:@"Menlo" size:13] ?: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular]);
    [self setNeedsDisplay:YES];
}

- (void)setAlignment:(NSTextAlignment)alignment
{
    _alignment = alignment;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = self.alignment;
    style.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary *attrs = @{
        NSForegroundColorAttributeName: self.textColor ?: mc_white(),
        NSFontAttributeName: self.font ?: ([NSFont fontWithName:@"Menlo" size:13] ?: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular]),
        NSParagraphStyleAttributeName: style
    };

    CGFloat insetX = self.alignment == NSTextAlignmentRight ? 6.0 : 8.0;
    NSRect textRect = NSInsetRect(self.bounds, insetX, 2.0);
    [self.text drawInRect:textRect withAttributes:attrs];
}

@end

@implementation CommanderRowsOverlayView

- (BOOL)isOpaque
{
    return NO;
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    [self.panel drawRowsInOverlayView:self dirtyRect:dirtyRect];
}

@end

@implementation CommanderPanel

- (instancetype)initWithIndex:(NSInteger)index runtime:(CommanderRuntime *)runtime
{
    self = [super init];
    if (self) {
        _index = index;
        _runtime = runtime;
        _cursor = 0;
        _items = [NSMutableArray array];
    }
    return self;
}

- (void)setActive:(BOOL)active
{
    self.rootView.layer.borderColor = (active ? mc_cyan().CGColor : mc_line().CGColor);
    if (active) {
        self.header.stringValue = [NSString stringWithFormat:@"[*] Panel %ld", (long)(self.index + 1)];
        self.header.textColor = mc_cyan();
        self.header.font = [NSFont fontWithName:@"Menlo-Bold" size:12] ?: [NSFont boldSystemFontOfSize:12];
        self.pathLabel.textColor = mc_white();
    } else {
        self.header.stringValue = [NSString stringWithFormat:@"[ ] Panel %ld", (long)(self.index + 1)];
        self.header.textColor = [NSColor colorWithCalibratedRed:0.45 green:0.83 blue:0.90 alpha:1.0];
        self.header.font = [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont systemFontOfSize:12];
        self.pathLabel.textColor = [NSColor colorWithCalibratedRed:0.75 green:0.84 blue:0.98 alpha:1.0];
    }
}

- (void)setPathText:(NSString *)text
{
    self.pathLabel.stringValue = [NSString stringWithFormat:@"[ %@ ]", text ?: @""];
}

- (void)setRows:(const commander_render_row_t *)rows count:(NSInteger)count cursor:(NSInteger)cursor
{
    [self.items removeAllObjects];

    if (rows && count > 0) {
        for (NSInteger i = 0; i < count; i++) {
            const commander_render_row_t *row = &rows[i];
            NSDictionary *item = @{
                @"name": str_from_c(row->name),
                @"size": str_from_c(row->size),
                @"modified": str_from_c(row->modified),
                @"flags": @(row->flags)
            };
            [self.items addObject:item];
        }
    }

    if (self.items.count == 0) {
        self.cursor = 0;
    } else {
        NSInteger maxIndex = (NSInteger)self.items.count - 1;
        self.cursor = cursor < 0 ? 0 : (cursor > maxIndex ? maxIndex : cursor);
    }

    self.updatingCursor = YES;
    @try {
        [self.table reloadData];
        if (self.items.count > 0) {
            NSIndexSet *selection = [NSIndexSet indexSetWithIndex:self.cursor];
            [self.table selectRowIndexes:selection byExtendingSelection:NO];
            [self.table scrollRowToVisible:self.cursor];
        }
    } @finally {
        self.updatingCursor = NO;
    }
    [self refreshFooter];
    [self.rowsOverlay setNeedsDisplay:YES];
}

- (void)applyCursor:(NSInteger)cursor
{
    if (self.items.count == 0) {
        self.cursor = 0;
        return;
    }
    NSInteger maxIndex = (NSInteger)self.items.count - 1;
    NSInteger newCursor = cursor < 0 ? 0 : (cursor > maxIndex ? maxIndex : cursor);
    if (newCursor == self.cursor && self.table.selectedRow == newCursor) {
        return;
    }
    NSInteger oldCursor = self.cursor;
    self.cursor = newCursor;

    self.updatingCursor = YES;
    @try {
        NSIndexSet *selection = [NSIndexSet indexSetWithIndex:self.cursor];
        [self.table selectRowIndexes:selection byExtendingSelection:NO];
        NSMutableIndexSet *changedRows = [NSMutableIndexSet indexSetWithIndex:self.cursor];
        if (oldCursor >= 0 && oldCursor < (NSInteger)self.items.count) {
            [changedRows addIndex:oldCursor];
        }
        [self.table reloadDataForRowIndexes:changedRows columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.table.numberOfColumns)]];
        [self.table scrollRowToVisible:self.cursor];
        [self refreshFooter];
    } @finally {
        self.updatingCursor = NO;
    }
    [self.rowsOverlay setNeedsDisplay:YES];
}

- (NSInteger)selectedRowIndex
{
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.items.count) {
        return -1;
    }
    return row;
}

- (void)refreshFooter
{
    NSInteger row = [self selectedRowIndex];
    if (row < 0 || row >= (NSInteger)self.items.count) {
        self.hintLabel.stringValue = @"";
        return;
    }

    NSDictionary *item = self.items[row];
    NSString *name = item[@"name"] ?: @"";
    NSString *size = item[@"size"] ?: @"";
    NSString *modified = item[@"modified"] ?: @"";
    self.hintLabel.stringValue = [NSString stringWithFormat:@" %@   %@   %@", name, size, modified];
}

- (void)emitKeyEvent:(NSEvent *)event
{
    commander_render_event_t data = {};
    data.type = COMMANDER_EVENT_KEY;
    data.panel = (int32_t)self.index;
    data.key_code = (int32_t)event.keyCode;
    data.modifiers = (uint32_t)event.modifierFlags;
    data.row = (int32_t)[self selectedRowIndex];
    data.x = event.locationInWindow.x;
    data.y = event.locationInWindow.y;
    [self.runtime pushEvent:data];
}

- (void)emitSyntheticKeyCode:(int32_t)keyCode modifiers:(uint32_t)modifiers
{
    commander_render_event_t data = {};
    data.type = COMMANDER_EVENT_KEY;
    data.panel = (int32_t)self.index;
    data.key_code = keyCode;
    data.modifiers = modifiers;
    data.row = (int32_t)[self selectedRowIndex];
    [self.runtime pushEvent:data];
}

- (void)emitTabEvent:(NSEvent *)event
{
    commander_render_event_t data = {};
    data.type = COMMANDER_EVENT_TAB;
    data.panel = (int32_t)self.index;
    data.key_code = (int32_t)event.keyCode;
    data.modifiers = (uint32_t)event.modifierFlags;
    data.row = (int32_t)[self selectedRowIndex];
    [self.runtime pushEvent:data];
}

- (void)emitQuitEvent:(NSEvent *)event
{
    commander_render_event_t data = {};
    data.type = COMMANDER_EVENT_QUIT;
    data.panel = (int32_t)self.index;
    data.key_code = (int32_t)event.keyCode;
    data.modifiers = (uint32_t)event.modifierFlags;
    data.row = (int32_t)[self selectedRowIndex];
    [self.runtime pushEvent:data];
}

- (void)emitMouseDownEvent:(NSEvent *)event row:(NSInteger)row
{
    commander_render_event_t data = {};
    data.type = COMMANDER_EVENT_MOUSE_DOWN;
    data.panel = (int32_t)self.index;
    data.modifiers = (uint32_t)event.modifierFlags;
    data.row = (int32_t)row;
    data.button = (int32_t)event.buttonNumber;
    data.click_count = (uint32_t)event.clickCount;
    data.x = event.locationInWindow.x;
    data.y = event.locationInWindow.y;
    [self.runtime pushEvent:data];
}

- (void)emitRowSelectedEvent:(NSInteger)row
{
    commander_render_event_t data = {};
    data.type = COMMANDER_EVENT_ROW_SELECTED;
    data.panel = (int32_t)self.index;
    data.row = (int32_t)row;
    [self.runtime pushEvent:data];
}

- (void)emitRowActivatedEvent:(NSEvent *)event row:(NSInteger)row
{
    commander_render_event_t data = {};
    data.type = COMMANDER_EVENT_ROW_ACTIVATED;
    data.panel = (int32_t)self.index;
    data.modifiers = (uint32_t)event.modifierFlags;
    data.row = (int32_t)row;
    data.button = (int32_t)event.buttonNumber;
    data.click_count = (uint32_t)event.clickCount;
    data.x = event.locationInWindow.x;
    data.y = event.locationInWindow.y;
    [self.runtime pushEvent:data];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.items.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)self.items.count) {
        return @"";
    }
    NSDictionary *item = self.items[row];
    NSString *identifier = tableColumn.identifier ?: @"name";
    return item[identifier] ?: @"";
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)self.items.count) {
        return nil;
    }

    NSDictionary *item = self.items[row];
    NSString *identifier = tableColumn.identifier ?: @"name";
    CommanderCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[CommanderCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, tableView.rowHeight)];
        cell.identifier = identifier;
        cell.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }

    BOOL isSelected = (row == self.cursor);
    uint32_t flags = [item[@"flags"] unsignedIntValue];
    BOOL isDirectory = (flags & COMMANDER_ROW_FLAG_DIRECTORY) != 0;
    BOOL isExecutable = (flags & COMMANDER_ROW_FLAG_EXECUTABLE) != 0;
    BOOL isParent = (flags & COMMANDER_ROW_FLAG_PARENT) != 0;
    BOOL isMarked = (flags & COMMANDER_ROW_FLAG_MARKED) != 0;

    NSString *value = item[identifier] ?: @"";
    if ([identifier isEqualToString:@"name"] && isMarked) {
        value = [NSString stringWithFormat:@"✓ %@", value];
    }
    cell.text = @"";
    cell.font = [NSFont fontWithName:@"Menlo" size:13] ?: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];

    if ([identifier isEqualToString:@"size"] || [identifier isEqualToString:@"modified"]) {
        cell.alignment = NSTextAlignmentRight;
        cell.textColor = isSelected ? NSColor.blackColor : [NSColor colorWithCalibratedRed:0.72 green:0.92 blue:1.00 alpha:1.0];
    } else {
        cell.alignment = NSTextAlignmentLeft;
        if (isSelected) {
            cell.textColor = NSColor.blackColor;
        } else if (isMarked) {
            cell.textColor = mc_cyan();
        } else if (isParent) {
            cell.textColor = mc_white();
        } else if (isDirectory) {
            cell.textColor = [NSColor colorWithCalibratedRed:0.86 green:0.92 blue:1.00 alpha:1.0];
        } else if (isExecutable) {
            cell.textColor = mc_green();
        } else {
            cell.textColor = mc_yellow();
        }
    }

    return cell;
}

- (void)drawRowsInTableView:(NSTableView *)tableView dirtyRect:(NSRect)dirtyRect
{
    if (self.items.count == 0) {
        return;
    }

    NSFont *font = [NSFont fontWithName:@"Menlo" size:13] ?: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];

    for (NSInteger row = 0; row < (NSInteger)self.items.count; row++) {
        NSRect rowRect = [tableView rectOfRow:row];
        if (NSIsEmptyRect(NSIntersectionRect(rowRect, dirtyRect))) {
            continue;
        }

        NSDictionary *item = self.items[row];
        BOOL isSelected = (row == self.cursor);
        uint32_t flags = [item[@"flags"] unsignedIntValue];
        BOOL isDirectory = (flags & COMMANDER_ROW_FLAG_DIRECTORY) != 0;
        BOOL isExecutable = (flags & COMMANDER_ROW_FLAG_EXECUTABLE) != 0;
        BOOL isParent = (flags & COMMANDER_ROW_FLAG_PARENT) != 0;
        BOOL isMarked = (flags & COMMANDER_ROW_FLAG_MARKED) != 0;

        NSColor *nameColor = mc_yellow();
        if (isSelected) {
            nameColor = NSColor.blackColor;
        } else if (isMarked) {
            nameColor = mc_cyan();
        } else if (isParent) {
            nameColor = mc_white();
        } else if (isDirectory) {
            nameColor = [NSColor colorWithCalibratedRed:0.86 green:0.92 blue:1.00 alpha:1.0];
        } else if (isExecutable) {
            nameColor = mc_green();
        }
        NSColor *metaColor = isSelected ? NSColor.blackColor : [NSColor colorWithCalibratedRed:0.72 green:0.92 blue:1.00 alpha:1.0];

        for (NSInteger columnIndex = 0; columnIndex < (NSInteger)tableView.tableColumns.count; columnIndex++) {
            NSTableColumn *column = tableView.tableColumns[columnIndex];
            NSString *identifier = column.identifier ?: @"name";
            NSString *value = item[identifier] ?: @"";
            NSTextAlignment alignment = NSTextAlignmentLeft;
            NSColor *textColor = nameColor;

            if ([identifier isEqualToString:@"name"]) {
                if (isMarked) {
                    value = [NSString stringWithFormat:@"✓ %@", value];
                }
            } else {
                alignment = NSTextAlignmentRight;
                textColor = metaColor;
            }

            NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
            style.alignment = alignment;
            style.lineBreakMode = NSLineBreakByTruncatingTail;

            NSDictionary *attrs = @{
                NSForegroundColorAttributeName: textColor,
                NSFontAttributeName: font,
                NSParagraphStyleAttributeName: style
            };

            NSRect cellRect = NSIntersectionRect(rowRect, [tableView rectOfColumn:columnIndex]);
            CGFloat insetX = alignment == NSTextAlignmentRight ? 4.0 : 4.0;
            NSRect textRect = NSInsetRect(cellRect, insetX, 2.0);
            [value drawInRect:textRect withAttributes:attrs];
        }
    }
}

- (void)drawRowsInOverlayView:(NSView *)overlay dirtyRect:(NSRect)dirtyRect
{
    if (self.items.count == 0 || !self.table) {
        return;
    }

    NSFont *font = [NSFont fontWithName:@"Menlo" size:13] ?: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    CGFloat headerHeight = self.table.headerView ? self.table.headerView.bounds.size.height : 24.0;
    CGFloat rowStep = self.table.rowHeight + self.table.intercellSpacing.height;
    CGFloat visibleOriginY = self.table.visibleRect.origin.y;
    NSRect bodyRect = NSMakeRect(0.0, headerHeight, overlay.bounds.size.width, overlay.bounds.size.height - headerHeight);

    [mc_header_dark() setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, overlay.bounds.size.width, headerHeight));

    NSFont *headerFont = [NSFont fontWithName:@"Menlo-Bold" size:12] ?: [NSFont boldSystemFontOfSize:12];
    NSDictionary *headerAttrs = @{
        NSForegroundColorAttributeName: mc_white(),
        NSFontAttributeName: headerFont
    };
    CGFloat headerX = 0.0;
    for (NSInteger columnIndex = 0; columnIndex < (NSInteger)self.table.tableColumns.count; columnIndex++) {
        NSTableColumn *column = self.table.tableColumns[columnIndex];
        NSString *title = column.title ?: @"";
        NSRect headerRect = NSMakeRect(headerX + 4.0, 3.0, column.width - 8.0, headerHeight - 4.0);
        [title drawInRect:headerRect withAttributes:headerAttrs];
        headerX += column.width;
    }

    [[mc_line() colorWithAlphaComponent:0.55] setFill];
    CGFloat separatorX = 0.0;
    for (NSInteger columnIndex = 0; columnIndex < (NSInteger)self.table.tableColumns.count - 1; columnIndex++) {
        separatorX += self.table.tableColumns[columnIndex].width;
        NSRectFill(NSMakeRect(floor(separatorX), 0.0, 1.0, overlay.bounds.size.height));
    }

    [NSGraphicsContext saveGraphicsState];
    NSRectClip(bodyRect);

    for (NSInteger row = 0; row < (NSInteger)self.items.count; row++) {
        NSRect rowRect = NSMakeRect(0.0, headerHeight + (((CGFloat)row - 1.0) * rowStep) - visibleOriginY, overlay.bounds.size.width, self.table.rowHeight);
        if (rowRect.origin.y >= overlay.bounds.size.height) {
            break;
        }
        if (NSIsEmptyRect(NSIntersectionRect(rowRect, overlay.bounds)) || NSIsEmptyRect(NSIntersectionRect(rowRect, dirtyRect))) {
            continue;
        }

        NSDictionary *item = self.items[row];
        BOOL isSelected = (row == self.cursor);
        uint32_t flags = [item[@"flags"] unsignedIntValue];
        BOOL isDirectory = (flags & COMMANDER_ROW_FLAG_DIRECTORY) != 0;
        BOOL isExecutable = (flags & COMMANDER_ROW_FLAG_EXECUTABLE) != 0;
        BOOL isParent = (flags & COMMANDER_ROW_FLAG_PARENT) != 0;
        BOOL isMarked = (flags & COMMANDER_ROW_FLAG_MARKED) != 0;

        NSColor *nameColor = mc_yellow();
        if (isSelected) {
            nameColor = NSColor.blackColor;
        } else if (isMarked) {
            nameColor = mc_cyan();
        } else if (isParent) {
            nameColor = mc_white();
        } else if (isDirectory) {
            nameColor = [NSColor colorWithCalibratedRed:0.86 green:0.92 blue:1.00 alpha:1.0];
        } else if (isExecutable) {
            nameColor = mc_green();
        }
        NSColor *metaColor = isSelected ? NSColor.blackColor : [NSColor colorWithCalibratedRed:0.72 green:0.92 blue:1.00 alpha:1.0];

        for (NSInteger columnIndex = 0; columnIndex < (NSInteger)self.table.tableColumns.count; columnIndex++) {
            NSTableColumn *column = self.table.tableColumns[columnIndex];
            NSString *identifier = column.identifier ?: @"name";
            NSString *value = item[identifier] ?: @"";
            NSTextAlignment alignment = NSTextAlignmentLeft;
            NSColor *textColor = nameColor;

            if ([identifier isEqualToString:@"name"]) {
                if (isMarked) {
                    value = [NSString stringWithFormat:@"✓ %@", value];
                }
            } else {
                alignment = NSTextAlignmentRight;
                textColor = metaColor;
            }

            NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
            style.alignment = alignment;
            style.lineBreakMode = NSLineBreakByTruncatingTail;

            NSDictionary *attrs = @{
                NSForegroundColorAttributeName: textColor,
                NSFontAttributeName: font,
                NSParagraphStyleAttributeName: style
            };

            CGFloat columnX = 0.0;
            for (NSInteger prior = 0; prior < columnIndex; prior++) {
                columnX += self.table.tableColumns[prior].width;
            }
            NSRect columnRect = NSMakeRect(columnX, rowRect.origin.y, column.width, rowRect.size.height);
            NSRect cellRect = NSIntersectionRect(rowRect, columnRect);
            CGFloat insetX = alignment == NSTextAlignmentRight ? 4.0 : 4.0;
            NSRect textRect = NSInsetRect(cellRect, insetX, 2.0);
            [value drawInRect:textRect withAttributes:attrs];
        }
    }
    [NSGraphicsContext restoreGraphicsState];
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
    CommanderRowView *rowView = [[CommanderRowView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, tableView.rowHeight)];
    rowView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    return rowView;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if (self.updatingCursor) {
        return;
    }
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.items.count) {
        return;
    }
    NSInteger oldCursor = self.cursor;
    self.cursor = row;
    NSMutableIndexSet *changedRows = [NSMutableIndexSet indexSetWithIndex:self.cursor];
    if (oldCursor >= 0 && oldCursor < (NSInteger)self.items.count) {
        [changedRows addIndex:oldCursor];
    }
    [self.table reloadDataForRowIndexes:changedRows columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.table.numberOfColumns)]];
    [self refreshFooter];
    [self.rowsOverlay setNeedsDisplay:YES];
    [self.runtime focusPanel:self.index];
    [self emitRowSelectedEvent:row];
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    return row >= 0 && row < (NSInteger)self.items.count;
}

@end

static NSColor *mc_blue(void)
{
    return [NSColor colorWithCalibratedRed:0.05 green:0.14 blue:0.74 alpha:1.0];
}

static NSColor *mc_blue_dark(void)
{
    return [NSColor colorWithCalibratedRed:0.03 green:0.06 blue:0.45 alpha:1.0];
}

static NSColor *mc_cyan(void)
{
    return [NSColor colorWithCalibratedRed:0.12 green:0.80 blue:0.86 alpha:1.0];
}

static NSColor *mc_header_dark(void)
{
    return [NSColor colorWithCalibratedRed:0.16 green:0.17 blue:0.19 alpha:1.0];
}

static NSColor *mc_line(void)
{
    return [NSColor colorWithCalibratedRed:0.63 green:0.77 blue:1.00 alpha:1.0];
}

static NSColor *mc_white(void)
{
    return [NSColor colorWithCalibratedRed:0.90 green:0.94 blue:1.00 alpha:1.0];
}

static NSColor *mc_yellow(void)
{
    return [NSColor colorWithCalibratedRed:1.00 green:0.88 blue:0.33 alpha:1.0];
}

static NSColor *mc_green(void)
{
    return [NSColor colorWithCalibratedRed:0.43 green:1.00 blue:0.53 alpha:1.0];
}

static NSTextField *mc_label(NSRect frame, NSString *text, NSColor *textColor, NSFont *font, NSTextAlignment alignment)
{
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text ?: @"";
    label.bezeled = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.alignment = alignment;
    label.textColor = textColor ?: NSColor.whiteColor;
    label.font = font ?: [NSFont systemFontOfSize:12];
    return label;
}

static NSString *str_from_c(const char *text)
{
    if (!text) {
        return @"";
    }
    NSString *value = [NSString stringWithUTF8String:text];
    return value ?: @"";
}

static void add_column(NSTableView *table, NSString *identifier, NSString *title, CGFloat width)
{
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.width = width;
    column.minWidth = width;
    column.resizingMask = NSTableColumnNoResizing;
    [table addTableColumn:column];
}

static CommanderPanel *build_panel(NSView *parent, CGFloat x, CGFloat y, CGFloat w, CGFloat h, NSInteger index, CommanderRuntime *runtime)
{
    CommanderPanel *panel = [[CommanderPanel alloc] initWithIndex:index runtime:runtime];

    NSView *panelView = [[NSView alloc] initWithFrame:NSMakeRect(x, y, w, h)];
    panelView.identifier = [NSString stringWithFormat:@"commander.panel.%ld", (long)index];
    panelView.wantsLayer = YES;
    panelView.layer.backgroundColor = mc_blue().CGColor;
    panelView.layer.borderWidth = 1.0;
    panelView.layer.borderColor = mc_line().CGColor;

    NSTextField *header = mc_label(NSMakeRect(8, h - 22, w - 16, 16),
                                   [NSString stringWithFormat:@"[ ] Panel %ld", (long)(index + 1)],
                                   [NSColor colorWithCalibratedRed:0.45 green:0.83 blue:0.90 alpha:1.0],
                                   [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont systemFontOfSize:12],
                                   NSTextAlignmentLeft);
    header.identifier = [NSString stringWithFormat:@"commander.panel.%ld.header", (long)index];

    NSTextField *pathLabel = mc_label(NSMakeRect(8, h - 40, w - 16, 16),
                                      @"[ ~ ]",
                                      mc_white(),
                                      [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont systemFontOfSize:12],
                                      NSTextAlignmentLeft);
    pathLabel.identifier = [NSString stringWithFormat:@"commander.panel.%ld.path", (long)index];

    CommanderTableView *table = [[CommanderTableView alloc] initWithFrame:NSMakeRect(6, 8, w - 12, h - 34)];
    table.identifier = [NSString stringWithFormat:@"commander.panel.%ld.table", (long)index];
    table.panel = panel;
    table.delegate = panel;
    table.dataSource = panel;
    table.rowHeight = 22.0;
    table.intercellSpacing = NSMakeSize(0, 1);
    table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    table.usesAlternatingRowBackgroundColors = NO;
    table.gridColor = NSColor.clearColor;
    table.gridStyleMask = NSTableViewGridNone;
    table.backgroundColor = mc_blue();
    table.focusRingType = NSFocusRingTypeNone;
    table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    table.allowsMultipleSelection = NO;

    add_column(table, @"name", @"Name", MAX(180.0, w - 226.0));
    add_column(table, @"size", @"Size", 84.0);
    add_column(table, @"modified", @"Modify time", 122.0);

    NSTableColumn *nameCol = [table tableColumnWithIdentifier:@"name"];
    nameCol.resizingMask = NSTableColumnAutoresizingMask;
    nameCol.maxWidth = w;
    nameCol.minWidth = 140.0;

    NSDictionary *headerAttrs = @{
        NSForegroundColorAttributeName: mc_white(),
        NSFontAttributeName: [NSFont fontWithName:@"Menlo-Bold" size:12] ?: [NSFont boldSystemFontOfSize:12]
    };
    for (NSTableColumn *col in table.tableColumns) {
        NSTableHeaderCell *cell = col.headerCell;
        cell.drawsBackground = NO;
        cell.attributedStringValue = [[NSAttributedString alloc] initWithString:col.title attributes:headerAttrs];
    }
    table.headerView.wantsLayer = YES;
    table.headerView.layer.backgroundColor = mc_header_dark().CGColor;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(6, 8, w - 12, h - 34)];
    scroll.hasVerticalScroller = NO;
    scroll.borderType = NSNoBorder;
    scroll.backgroundColor = mc_blue();
    scroll.drawsBackground = YES;
    scroll.documentView = table;

    CommanderRowsOverlayView *rowsOverlay = [[CommanderRowsOverlayView alloc] initWithFrame:scroll.frame];
    rowsOverlay.identifier = [NSString stringWithFormat:@"commander.panel.%ld.rowsOverlay", (long)index];
    rowsOverlay.panel = panel;
    rowsOverlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    rowsOverlay.wantsLayer = NO;

    NSTextField *hint = mc_label(NSMakeRect(8, 8, w - 16, 20),
                                 @"",
                                 mc_white(),
                                 [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular],
                                 NSTextAlignmentLeft);
    hint.identifier = [NSString stringWithFormat:@"commander.panel.%ld.footer", (long)index];
    hint.hidden = YES;
    hint.drawsBackground = YES;
    hint.backgroundColor = mc_blue_dark();

    panel.rootView = panelView;
    panel.header = header;
    panel.pathLabel = pathLabel;
    panel.table = table;
    panel.rowsOverlay = rowsOverlay;
    panel.hintLabel = hint;

    [panelView addSubview:header];
    [panelView addSubview:pathLabel];
    [panelView addSubview:scroll];
    [panelView addSubview:rowsOverlay positioned:NSWindowAbove relativeTo:scroll];
    [parent addSubview:panelView];

    return panel;
}

static void build_window_if_needed(CommanderRuntime *runtime)
{
    if (!runtime || runtime.shown) {
        return;
    }

    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    [app finishLaunching];

    CommanderAppDelegate *delegate = [[CommanderAppDelegate alloc] initWithRuntime:runtime];
    runtime.appDelegate = delegate;
    app.delegate = delegate;

    NSUInteger styleMask = NSWindowStyleMaskTitled |
                           NSWindowStyleMaskClosable |
                           NSWindowStyleMaskMiniaturizable;

    NSRect frame = NSMakeRect(80.0, 80.0, runtime.width, runtime.height);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:styleMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Crystal Commander Renderer";
    window.identifier = @"commander.mainWindow";
    window.delegate = delegate;
    [window setMinSize:NSMakeSize(980.0, 560.0)];
    [window center];

    NSMenu *menubar = [[NSMenu alloc] init];
    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    NSMenuItem *quitCmd = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(requestQuit:) keyEquivalent:@"q"];
    [quitCmd setTarget:delegate];
    [quitCmd setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [fileMenu addItem:quitCmd];
    NSMenuItem *quitCtrl = [[NSMenuItem alloc] initWithTitle:@"Quit (Ctrl+Q)" action:@selector(requestQuit:) keyEquivalent:@"q"];
    [quitCtrl setTarget:delegate];
    [quitCtrl setKeyEquivalentModifierMask:NSEventModifierFlagControl];
    [fileMenu addItem:quitCtrl];
    [fileItem setSubmenu:fileMenu];
    [menubar addItem:fileItem];
    [NSApp setMainMenu:menubar];

    NSView *content = window.contentView;
    content.identifier = @"commander.root";
    content.wantsLayer = YES;
    content.layer.backgroundColor = mc_blue_dark().CGColor;

    const CGFloat topBarHeight = 24.0;
    const CGFloat commandBarHeight = 24.0;
    const CGFloat keyBarHeight = 24.0;
    const CGFloat panelBottom = commandBarHeight + keyBarHeight + 8.0;
    const CGFloat panelTop = runtime.height - topBarHeight - 8.0;
    CGFloat panelHeight = panelTop - panelBottom;
    if (panelHeight < 260.0) {
        panelHeight = 260.0;
    }

    NSView *topBar = [[NSView alloc] initWithFrame:NSMakeRect(0, runtime.height - topBarHeight, runtime.width, topBarHeight)];
    topBar.identifier = @"commander.topBar";
    topBar.wantsLayer = YES;
    topBar.layer.backgroundColor = mc_cyan().CGColor;
    [content addSubview:topBar];

    NSArray<NSString *> *menuNames = @[@"Left", @"File", @"Command", @"Options", @"Right"];
    CGFloat topX = 10.0;
    for (NSString *menuName in menuNames) {
        NSTextField *menuLabel = mc_label(NSMakeRect(topX, 2, 120, topBarHeight - 4),
                                          menuName,
                                          NSColor.blackColor,
                                          [NSFont fontWithName:@"Menlo-Bold" size:13] ?: [NSFont boldSystemFontOfSize:13],
                                          NSTextAlignmentLeft);
        [topBar addSubview:menuLabel];
        topX += 104.0;
    }

    NSView *commandBar = [[NSView alloc] initWithFrame:NSMakeRect(0, keyBarHeight, runtime.width, commandBarHeight)];
    commandBar.identifier = @"commander.commandBar";
    commandBar.wantsLayer = YES;
    commandBar.layer.backgroundColor = NSColor.blackColor.CGColor;
    [content addSubview:commandBar];

    NSTextField *status = mc_label(NSMakeRect(8, 4, runtime.width - 16, commandBarHeight - 6),
                                   @"Ready",
                                   mc_white(),
                                   [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular],
                                   NSTextAlignmentLeft);
    status.identifier = @"commander.status";
    [commandBar addSubview:status];
    runtime.statusLabel = status;

    NSView *keyBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, runtime.width, keyBarHeight)];
    keyBar.identifier = @"commander.keyBar";
    keyBar.wantsLayer = YES;
    keyBar.layer.backgroundColor = mc_blue_dark().CGColor;
    [content addSubview:keyBar];

    NSArray<NSString *> *keys = @[@"1Help", @"2Menu", @"3View", @"4Edit", @"5Copy", @"6RenMov", @"7Mkdir", @"8Delete", @"9PullDn", @"10Quit"];
    CGFloat keyWidth = floor(runtime.width / (CGFloat)keys.count);
    for (NSUInteger i = 0; i < keys.count; i++) {
        NSView *segment = [[NSView alloc] initWithFrame:NSMakeRect(i * keyWidth, 2, keyWidth - 2, keyBarHeight - 4)];
        segment.wantsLayer = YES;
        segment.layer.backgroundColor = mc_cyan().CGColor;
        [keyBar addSubview:segment];

        NSTextField *keyLabel = mc_label(NSMakeRect(6, 2, keyWidth - 10, keyBarHeight - 8),
                                         keys[i],
                                         NSColor.blackColor,
                                         [NSFont fontWithName:@"Menlo-Bold" size:12] ?: [NSFont boldSystemFontOfSize:12],
                                         NSTextAlignmentLeft);
        [segment addSubview:keyLabel];
    }

    [runtime.panels removeAllObjects];
    CGFloat margin = 8.0;
    CGFloat panelWidth = (runtime.width - margin * (runtime.panelCount + 1)) / runtime.panelCount;
    for (NSInteger i = 0; i < runtime.panelCount; i++) {
        CGFloat x = margin + (panelWidth + margin) * i;
        CommanderPanel *panel = build_panel(content, x, panelBottom, panelWidth, panelHeight, i, runtime);
        [runtime.panels addObject:panel];
    }

    runtime.window = window;
    runtime.shown = YES;
    runtime.running = YES;

    [runtime focusPanel:0];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

static CommanderRuntime *runtime_from_handle(void *handle)
{
    if (!handle) {
        return nil;
    }
    return (__bridge CommanderRuntime *)handle;
}

extern "C" void *commander_renderer_create(int32_t panel_count, int32_t width, int32_t height)
{
    @autoreleasepool {
        CommanderRuntime *runtime = [[CommanderRuntime alloc] initWithPanelCount:panel_count width:width height:height];
        return (__bridge_retained void *)runtime;
    }
}

extern "C" void commander_renderer_destroy(void *handle)
{
    if (!handle) {
        return;
    }

    @autoreleasepool {
        CommanderRuntime *runtime = (__bridge_transfer CommanderRuntime *)handle;
        if (runtime.running) {
            [runtime requestStop];
        }
    }
}

extern "C" int32_t commander_renderer_show(void *handle)
{
    @autoreleasepool {
        CommanderRuntime *runtime = runtime_from_handle(handle);
        if (!runtime) {
            return 0;
        }
        build_window_if_needed(runtime);
        return runtime.shown ? 1 : 0;
    }
}

extern "C" int32_t commander_renderer_pump(void *handle, int32_t wait_ms)
{
    @autoreleasepool {
        CommanderRuntime *runtime = runtime_from_handle(handle);
        if (!runtime || !runtime.shown || !runtime.running) {
            return 0;
        }

        NSTimeInterval waitTime = wait_ms <= 0 ? 0.0 : (NSTimeInterval)wait_ms / 1000.0;
        NSDate *deadline = waitTime > 0.0 ? [NSDate dateWithTimeIntervalSinceNow:waitTime] : [NSDate distantPast];
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                            untilDate:deadline
                                               inMode:NSDefaultRunLoopMode
                                              dequeue:YES];
        if (event) {
            [NSApp sendEvent:event];
        }

        // Drain any immediately available events to keep UI responsive.
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                           untilDate:[NSDate distantPast]
                                              inMode:NSDefaultRunLoopMode
                                             dequeue:YES])) {
            [NSApp sendEvent:event];
        }

        [NSApp updateWindows];
        return runtime.running ? 1 : 0;
    }
}

extern "C" void commander_renderer_stop(void *handle)
{
    @autoreleasepool {
        CommanderRuntime *runtime = runtime_from_handle(handle);
        if (!runtime) {
            return;
        }
        [runtime requestStop];
    }
}

extern "C" int32_t commander_renderer_poll_event(void *handle, commander_render_event_t *out_event)
{
    @autoreleasepool {
        CommanderRuntime *runtime = runtime_from_handle(handle);
        if (!runtime || !out_event) {
            return 0;
        }
        return [runtime popEvent:out_event] ? 1 : 0;
    }
}

extern "C" void commander_renderer_set_active_panel(void *handle, int32_t panel_index)
{
    @autoreleasepool {
        CommanderRuntime *runtime = runtime_from_handle(handle);
        if (!runtime || !runtime.shown) {
            return;
        }
        [runtime focusPanel:panel_index];
    }
}

extern "C" void commander_renderer_set_status_text(void *handle, const char *text)
{
    @autoreleasepool {
        CommanderRuntime *runtime = runtime_from_handle(handle);
        if (!runtime || !runtime.statusLabel) {
            return;
        }
        runtime.statusLabel.stringValue = str_from_c(text);
    }
}

extern "C" void commander_renderer_set_panel_path(void *handle, int32_t panel_index, const char *path)
{
    @autoreleasepool {
        CommanderRuntime *runtime = runtime_from_handle(handle);
        if (!runtime || !runtime.shown) {
            return;
        }
        if (panel_index < 0 || panel_index >= (int32_t)runtime.panels.count) {
            return;
        }
        CommanderPanel *panel = runtime.panels[panel_index];
        [panel setPathText:str_from_c(path)];
    }
}

extern "C" void commander_renderer_set_panel_rows(void *handle, int32_t panel_index, const commander_render_row_t *rows, int32_t row_count, int32_t cursor)
{
    @autoreleasepool {
        CommanderRuntime *runtime = runtime_from_handle(handle);
        if (!runtime || !runtime.shown) {
            return;
        }
        if (panel_index < 0 || panel_index >= (int32_t)runtime.panels.count) {
            return;
        }
        if (row_count < 0) {
            row_count = 0;
        }
        CommanderPanel *panel = runtime.panels[panel_index];
        [panel setRows:rows count:row_count cursor:cursor];
    }
}

extern "C" void commander_renderer_set_panel_cursor(void *handle, int32_t panel_index, int32_t selected_index)
{
    @autoreleasepool {
        CommanderRuntime *runtime = runtime_from_handle(handle);
        if (!runtime || !runtime.shown) {
            return;
        }
        if (panel_index < 0 || panel_index >= (int32_t)runtime.panels.count) {
            return;
        }
        CommanderPanel *panel = runtime.panels[panel_index];
        [panel applyCursor:selected_index];
    }
}

extern "C" void commander_renderer_get_mouse_position(void *handle, double *x, double *y)
{
    @autoreleasepool {
        CommanderRuntime *runtime = runtime_from_handle(handle);
        if (x) {
            *x = 0.0;
        }
        if (y) {
            *y = 0.0;
        }
        if (!runtime || !runtime.window) {
            return;
        }

        NSPoint point = [runtime.window mouseLocationOutsideOfEventStream];
        if (x) {
            *x = point.x;
        }
        if (y) {
            *y = point.y;
        }
    }
}

extern "C" void commander_renderer_set_mouse_visible(int32_t visible)
{
    static BOOL mouseHidden = NO;
    if (visible) {
        if (mouseHidden) {
            [NSCursor unhide];
            mouseHidden = NO;
        }
    } else {
        if (!mouseHidden) {
            [NSCursor hide];
            mouseHidden = YES;
        }
    }
}

extern "C" void commander_renderer_run(int panel_count)
{
    void *handle = commander_renderer_create(panel_count, 1360, 860);
    if (!handle) {
        return;
    }

    if (!commander_renderer_show(handle)) {
        commander_renderer_destroy(handle);
        return;
    }

    while (commander_renderer_pump(handle, 16) == 1) {
    }

    commander_renderer_destroy(handle);
}
