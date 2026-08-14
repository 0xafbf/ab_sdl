
package main

import "core:fmt"
import "core:mem"

import win32 "core:sys/windows"


eprintf :: fmt.eprintf;

//  events that are being whatched now.
//  May change if needed
FSW_WATCHING_EVENTS: win32.DWORD = (
    win32.FILE_NOTIFY_CHANGE_FILE_NAME
    | win32.FILE_NOTIFY_CHANGE_DIR_NAME
    | win32.FILE_NOTIFY_CHANGE_LAST_WRITE
)


FSW :: struct {
    allocator : mem.Allocator,
    iocp_handler: win32.HANDLE,
    buffer: []byte,
    fws_id_list: [dynamic]^FSW_ID
}

FSW_ID :: struct {
    overlapped: win32.OVERLAPPED,
    handle: win32.HANDLE,
    path: string
}

FSW_Event_Type :: enum {
    CREATED,
    REMOVED,
    MODIFIED,
    RENAMED,
}

FSW_Event :: struct {
    filename: string,
    old_filename:string,
    event: FSW_Event_Type
}

FSW_Loop_Type :: enum win32.DWORD {
    NONBLOCKING = 0,
    BLOCKING = win32.INFINITE
}

fsw_create :: proc ( buffer_size:= 16 * 1024, allocator:= context.allocator ) -> (FSW, win32.DWORD) {
    iocp := win32.CreateIoCompletionPort(win32.INVALID_HANDLE, nil, 0,1);
    if iocp == win32.INVALID_HANDLE do return FSW{}, win32.GetLastError();

    return FSW{
        allocator = allocator,
        iocp_handler = iocp,
        buffer = make([]byte, buffer_size, allocator),
        fws_id_list = [dynamic]^FSW_ID{}
    }, 0;
}

fsw_add_dir :: proc (fsw: ^FSW, path: string) -> win32.DWORD {
    wide_path := win32.utf8_to_wstring( path, context.temp_allocator );
    handle    := win32.CreateFileW( wide_path ,
        win32.FILE_LIST_DIRECTORY,
        win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE | win32.FILE_SHARE_DELETE,
        nil,
        win32.OPEN_EXISTING,
        win32.FILE_FLAG_BACKUP_SEMANTICS | win32.FILE_FLAG_OVERLAPPED,
        nil
    );

    if handle == win32.INVALID_HANDLE {
        eprintf("ERROR: CreateFileW\n");
        return win32.GetLastError();
    }

    if win32.CreateIoCompletionPort(handle, fsw.iocp_handler , 0, 1) == win32.INVALID_HANDLE {
        eprintf("ERROR: CreateIoCompletionPort\n");
        return win32.GetLastError();
    }

    fsw_id :      = new( FSW_ID, fsw.allocator );
    fsw_id.handle = handle;
    fsw_id.path   = path;

    append(&fsw.fws_id_list, fsw_id );

    if win32.ReadDirectoryChangesW(
        fsw_id.handle,
        &fsw.buffer[0],
        u32( len(fsw.buffer) ),
        true,
        FSW_WATCHING_EVENTS,
        nil,
        &fsw_id.overlapped,
        nil) == win32.BOOL(false)
    {
        eprintf( "ReadDirectoryChangesW failed! \n");
        return win32.GetLastError();
    }

    return 0;
}

fsw_get_events :: proc ( fsw: ^FSW, loop_kind:= FSW_Loop_Type.NONBLOCKING )  -> []FSW_Event {
    overlapped: ^win32.OVERLAPPED;
    n_of_bytes := win32.DWORD(0);
    comp_key   := win32.ULONG_PTR(0); //have no idea why i need this, but it wont work without it

    if win32.GetQueuedCompletionStatus(fsw.iocp_handler, &n_of_bytes, &comp_key, &overlapped, win32.DWORD(loop_kind) ) == win32.BOOL(false) {
        return []FSW_Event{};
    }

    events := make( [dynamic]FSW_Event, context.temp_allocator );
    event_old_filename:= "";

    notifications := (^win32.FILE_NOTIFY_INFORMATION)( &fsw.buffer[0] );

    for {

        filename_len    := int( notifications.file_name_length )

        filename_w      := win32.wstring(&notifications.file_name[0])

        filename, _err  := win32.wstring_to_utf8(filename_w, filename_len / size_of(u16))

        action          := notifications.action

        event_filename := filename;
        event_event_type: FSW_Event_Type;

        switch action {
            case win32.FILE_ACTION_ADDED:
                event_event_type = .CREATED;
            case win32.FILE_ACTION_REMOVED:
                event_event_type = .REMOVED;
            case win32.FILE_ACTION_MODIFIED:
                event_event_type = .MODIFIED;
            case win32.FILE_ACTION_RENAMED_OLD_NAME:
                event_old_filename = event_filename;
            case win32.FILE_ACTION_RENAMED_NEW_NAME:
                event_event_type = .RENAMED;
            case:
                eprintf("{} - Unknow action {} \n", event_filename, action );
        }

        // Transform rename_old, rename_new into one event
        if action != win32.FILE_ACTION_RENAMED_OLD_NAME {
            append(&events, FSW_Event{ event_filename, event_old_filename, event_event_type });
            event_old_filename = "";
        }

        if notifications.next_entry_offset == 0 do break;
        notifications = (^win32.FILE_NOTIFY_INFORMATION)( uintptr(notifications) + uintptr(notifications.next_entry_offset) );
    }

    //  When event is captured i need to call it again
    //  this is the right way ??

    fsw_id := (^FSW_ID)(overlapped);
    if win32.ReadDirectoryChangesW(
        fsw_id.handle,
        &fsw.buffer[0],
        u32( len(fsw.buffer) ),
        true ,
        FSW_WATCHING_EVENTS,
        nil ,
        &fsw_id.overlapped,
        nil ) == win32.BOOL(false)
    {
        eprintf( "ReadDirectoryChangesW failed! \n");
    }

    return events[:];
}

fsw_destroy :: proc( fsw: ^ FSW ) {
    for ptr in fsw.fws_id_list {
        win32.CloseHandle(ptr.handle);
        free(ptr);
    }
    win32.CloseHandle( fsw.iocp_handler );
    delete(fsw.fws_id_list);
    delete(fsw.buffer);
}
