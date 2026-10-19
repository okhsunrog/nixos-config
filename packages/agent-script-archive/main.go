// agent-script-archive records Fleet script files before allowing their open.
package main

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

const (
	work      = "/var/lib/corporate-agent-work"
	archive   = "/var/lib/corporate-agent-archive"
	openPerm  = 0x10000
	maxScript = 8 << 20
)

func main() {
	log.SetFlags(log.LstdFlags | log.LUTC)
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	// FAN_MARK_FILESYSTEM observes every open on the marked filesystem. Keeping
	// the archive on that filesystem would let the collector block on its own
	// archive I/O. Refuse a missing/incorrect work mount before arming it.
	var workStat, archiveStat syscall.Stat_t
	if err := syscall.Stat(work, &workStat); err != nil {
		return err
	}
	if err := syscall.Stat(archive, &archiveStat); err != nil {
		return err
	}
	if workStat.Dev == archiveStat.Dev {
		return fmt.Errorf("%s must be a separate filesystem from %s", work, archive)
	}
	fd, _, errno := syscall.Syscall(syscall.SYS_FANOTIFY_INIT, 4|1, syscall.O_RDONLY|syscall.O_LARGEFILE|syscall.O_CLOEXEC, 0)
	if errno != 0 {
		return fmt.Errorf("fanotify_init: %w", errno)
	}
	defer syscall.Close(int(fd))
	path, _ := syscall.BytePtrFromString(work)
	_, _, errno = syscall.Syscall6(syscall.SYS_FANOTIFY_MARK, fd, 1|0x100, openPerm, ^uintptr(99), uintptr(unsafe.Pointer(path)), 0)
	if errno != 0 {
		return fmt.Errorf("fanotify mount mark: %w", errno)
	}
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	go func() { <-stop; syscall.Close(int(fd)); os.Exit(0) }()
	// Type=notify: agents cannot start until the permission listener is armed.
	if socket := os.Getenv("NOTIFY_SOCKET"); socket != "" {
		a := &syscall.SockaddrUnix{Name: socket}
		s, err := syscall.Socket(syscall.AF_UNIX, syscall.SOCK_DGRAM|syscall.SOCK_CLOEXEC, 0)
		if err != nil {
			return err
		}
		err = syscall.Sendto(s, []byte("READY=1"), 0, a)
		syscall.Close(s)
		if err != nil {
			return err
		}
	}
	log.Printf("ready: watching %s; archive %s", work, archive)
	buf := make([]byte, 64*1024)
	for {
		n, err := syscall.Read(int(fd), buf)
		if err == syscall.EINTR {
			continue
		}
		if err != nil {
			return err
		}
		for off := 0; off+24 <= n; {
			b := buf[off:n]
			length := int(binary.NativeEndian.Uint32(b[:4]))
			if length < 24 || off+length > n || b[4] != 3 {
				return fmt.Errorf("invalid fanotify metadata")
			}
			mask := binary.NativeEndian.Uint64(b[8:16])
			fileFD := int(int32(binary.NativeEndian.Uint32(b[16:20])))
			pid := int(int32(binary.NativeEndian.Uint32(b[20:24])))
			if mask&0x4000 != 0 {
				return fmt.Errorf("fanotify queue overflow; stopping listener and dependent agents")
			}
			if fileFD >= 0 {
				if mask&openPerm != 0 {
					allow := uint32(1)
					if err := capture(fileFD, pid); err != nil {
						allow = 2
						log.Printf("DENIED pid=%d: %v", pid, err)
					}
					response := make([]byte, 8)
					binary.NativeEndian.PutUint32(response[:4], uint32(fileFD))
					binary.NativeEndian.PutUint32(response[4:], allow)
					if _, err := syscall.Write(int(fd), response); err != nil {
						syscall.Close(fileFD)
						return err
					}
				}
				syscall.Close(fileFD)
			}
			off += length
		}
	}
}

func capture(fd, pid int) error {
	path, err := os.Readlink(fmt.Sprintf("/proc/self/fd/%d", fd))
	if err != nil {
		return err
	}
	// Fleet creates $TMPDIR/fleet-<execution-id>-<random>/script.
	path = strings.TrimSuffix(path, " (deleted)")
	if filepath.Base(path) != "script" || !strings.HasPrefix(filepath.Base(filepath.Dir(path)), "fleet-") {
		return nil
	}
	if !strings.HasPrefix(path, work+"/") {
		return fmt.Errorf("unexpected script path %q", path)
	}
	var stat syscall.Stat_t
	if err := syscall.Fstat(fd, &stat); err != nil {
		return err
	}
	if stat.Size > maxScript {
		return fmt.Errorf("script exceeds %d bytes", maxScript)
	}
	var space syscall.Statfs_t
	if err := syscall.Statfs(archive, &space); err != nil {
		return err
	}
	if space.Bavail*uint64(space.Bsize) < 256<<20 {
		return fmt.Errorf("less than 256 MiB free on archive filesystem")
	}
	data := make([]byte, int(stat.Size))
	n, err := syscall.Pread(fd, data, 0)
	if err != nil {
		return err
	}
	if n != len(data) {
		return io.ErrUnexpectedEOF
	}
	sum := sha256.Sum256(data)
	hash := hex.EncodeToString(sum[:])
	stamp := time.Now().UTC()
	dir, err := os.MkdirTemp(archive, stamp.Format("20060102T150405.000000000Z")+"-")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, "script"), data, 0600); err != nil {
		return err
	}
	cmd, _ := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", pid))
	cgroup, _ := os.ReadFile(fmt.Sprintf("/proc/%d/cgroup", pid))
	exe, _ := os.Readlink(fmt.Sprintf("/proc/%d/exe", pid))
	metadata := map[string]any{"captured_at": stamp, "pid": pid, "source": path, "sha256": hash, "size": len(data), "exe": exe, "argv": strings.Split(strings.TrimRight(string(cmd), "\x00"), "\x00"), "cgroup": string(cgroup), "event": "file_open_before_allow", "execution_confirmed": false}
	encoded, err := json.MarshalIndent(metadata, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, "metadata.json"), append(encoded, '\n'), 0600); err != nil {
		return err
	}
	// Persist the evidence before permitting the reader to proceed.
	for _, name := range []string{"script", "metadata.json", ".", ".."} {
		f, err := os.Open(filepath.Join(dir, name))
		if err != nil {
			return err
		}
		err = f.Sync()
		f.Close()
		if err != nil {
			return err
		}
	}
	log.Printf("CAPTURE pid=%d sha256=%s source=%q saved=%s", pid, hash, path, dir)
	return nil
}
