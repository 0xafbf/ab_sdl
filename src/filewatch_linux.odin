
package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

import "core:sys/linux"
import "core:sys/posix"
import "core:sys/unix"

eprintf :: fmt.eprintf;

FSW :: struct {
    allocator : mem.Allocator,
    inotify_fd: linux.Fd,
    watched_dir_paths: map[linux.Wd]string
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

FSW_Loop_Type :: enum u32 {
    NONBLOCKING,
    BLOCKING,
}

fsw_create :: proc ( buffer_size:= 16 * 1024, allocator:= context.allocator ) -> (FSW, int) {

    fd, errno := linux.inotify_init();

    return FSW{
        allocator = allocator,
        inotify_fd = fd,
    }, 0;
}

fsw_add_dir :: proc (fsw: ^FSW, dir: string) -> int {

    path := strings.clone_to_cstring(dir, context.temp_allocator)

    // fmt.println("adding dir:", path)
    entry: ^posix.dirent
    dp: posix.DIR = posix.opendir(path)
    if dp == nil {
        fmt.eprintln("opendir")
        return 1
    }

    wd, err := linux.inotify_add_watch(fsw.inotify_fd, path, {.MODIFY, .CREATE, .DELETE})
    if i32(wd) == -1 {
        fmt.eprintln("inotify_add_watch")
    }
    fsw.watched_dir_paths[wd] = dir


    entry = posix.readdir(dp)
    for entry != nil {
        defer entry = posix.readdir(dp)

        if entry.d_type == .DIR {

            string_ptr := &entry.d_name[0]
            entry_cname := cstring(string_ptr)
            entry_name := string(entry_cname)
            if strings.compare(entry_name, ".")  == 0 {
                continue
            }
            if strings.compare(entry_name, "..")  == 0 {
                continue
            }
            if strings.compare(entry_name, ".git")  == 0 {
                continue
            }

            if dir == "." {
                fsw_add_dir(fsw, entry_name)
            } else {
                child_path := fmt.aprintf("%s/%s", path, entry_name)
                fsw_add_dir(fsw, child_path)
            }
        }
    }
    return 0
}


fsw_get_events :: proc ( fsw: ^FSW, loop_kind:= FSW_Loop_Type.NONBLOCKING )  -> []FSW_Event {

    events := make( [dynamic]FSW_Event, context.temp_allocator );

    BUF_SIZE :: 64 * 1024
    buffer: [BUF_SIZE]byte

    notify_fds := []posix.pollfd{
        {posix.FD(fsw.inotify_fd), {.IN}, {}}
    }

    poll_result := posix.poll(raw_data(notify_fds), u32(len(notify_fds)), 0)

    if poll_result == 0 {
        return {}
    }


    length, read_err := os.read(os.Handle(fsw.inotify_fd), buffer[:])

    cursor: int = 0

    for cursor < length {
        event := (^linux.Inotify_Event)(&buffer[cursor])

        defer cursor += size_of(linux.Inotify_Event) + int(event.len)

        assert(event.len != 0)

        event_event_type: FSW_Event_Type;


        event_name_ptr := raw_data(&event.name)
        cname := cstring(event_name_ptr)
        name := string(cname)
        if .MODIFY in event.mask {
            event_event_type = .MODIFIED
        }
        if .CREATE in event.mask {
            event_event_type = .CREATED
        }
        if .DELETE in event.mask {
            event_event_type = .REMOVED
        }

        base := fsw.watched_dir_paths[event.wd]
        full_path := fmt.tprintf("%s/%s", base, name)

        append(&events, FSW_Event{ full_path, full_path, event_event_type });
    }
    return events[:];
}

fsw_destroy :: proc( fsw: ^ FSW ) {
}
