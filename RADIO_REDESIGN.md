# Radio View Redesign

## Overview
Redesigned the Radio view to simplify the layout and improve the skeleton loading state.

## Changes Made

### 1. Removed Sections
**Removed from Radio view:**
- ✅ "Hosted Stations" section (removed from both compact and wide layouts)
- ✅ "Featured Shows" section (removed from both compact and wide layouts)

**Simplified layout now shows:**
- Station card with artwork and controls
- Recently played history (if available)

### 2. Redesigned Radio Skeleton View
**Before:**
- Generic centered artwork placeholder
- Two horizontal shelf skeletons (for Hosted Stations and Featured Shows)
- Didn't match actual content structure

**After:**
- Station card skeleton matching actual layout:
  - "Featured Episode" kicker text placeholder
  - Title placeholder (30pt height)
  - Large artwork placeholder with gradient overlay
  - LIVE badge placeholder (red accent)
  - Control buttons placeholders at bottom
- History section skeleton:
  - Section title placeholder
  - 3 song row placeholders with artwork and text
  - Proper divider placement

**Layout matches actual RadioView structure:**
- Proper spacing using `AM.Spacing.shelfSpacing`
- Correct padding using `AM.Spacing.screenMargin`
- Uses proper placeholder colors (`appPlaceholderPrimary`, `appPlaceholderSecondary`, etc.)
- Maintains hero artwork corner radius

### 3. Removed Auto Mix Button
**Location:** `QueueView.swift`
- Removed the "Auto Mix" toggle button from the playback controls
- Kept: Shuffle, Repeat, Autoplay
- Removed animation binding for `autoMixEnabled`

**Before:** 4 control buttons (Shuffle, Repeat, Autoplay, Auto Mix)
**After:** 3 control buttons (Shuffle, Repeat, Autoplay)

## Files Modified

1. `/Twinskaraoke/Features/Radio/RadioView.swift`
   - Updated `compactRadioOverview` - removed `hostedStationsSection()` and `featuredShowsSection()`
   - Updated `wideRadioOverview` - removed `hostedStationsSection()` and `featuredShowsSection()`
   - Completely rewrote `RadioSkeletonView` to match actual content structure
   - New skeleton components: `stationCardSkeleton`, `historySkeleton`

2. `/Twinskaraoke/Features/Player/QueueView.swift`
   - Removed `QueueModeButton` for Auto Mix (`wand.and.stars` icon)
   - Removed animation binding for `autoMixEnabled`

## Build Status
✅ Build succeeded on iOS Simulator (iPhone 17, iOS 26.5)

## Visual Improvements
- Skeleton now accurately previews the actual content layout
- Cleaner, more focused Radio view without extra sections
- Simpler playback controls in queue view
- Better loading experience with realistic placeholders
