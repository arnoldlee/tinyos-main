#ifndef CX_LINK_DEBUG_H
#define CX_LINK_DEBUG_H

#ifndef LINK_DEBUG_FRAME_BOUNDARIES 
#define LINK_DEBUG_FRAME_BOUNDARIES 0
#endif

#ifndef DEBUG_LINK
#define DEBUG_LINK 0
#endif

#if DEBUG_LINK == 1
#define printf_LINK( ... ) printf( __VA_ARGS__ )
#else
#define printf_LINK(...)
#endif

#endif