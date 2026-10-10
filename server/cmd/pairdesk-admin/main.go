package main

import (
	"bufio"
	"flag"
	"fmt"
	"golang.org/x/term"
	"os"
	"pairdesk/server/internal/app"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	st, e := app.OpenStore(dataPath())
	if e != nil {
		fatal(e)
	}
	switch os.Args[1] {
	case "create-user":
		fs := flag.NewFlagSet("create-user", flag.ExitOnError)
		name := fs.String("name", "", "Full name")
		email := fs.String("email", "", "Email address")
		admin := fs.Bool("admin", false, "Grant admin marker")
		_ = fs.Parse(os.Args[2:])
		pw, e := password()
		if e != nil {
			fatal(e)
		}
		u, e := st.CreateUser(*name, *email, pw, *admin)
		if e != nil {
			fatal(e)
		}
		fmt.Printf("Created %s <%s> (id %s)\n", u.Name, u.Email, u.ID)
	case "disable-user", "enable-user":
		if len(os.Args) < 3 {
			usage()
		}
		err := st.SetUserEnabled(os.Args[2], os.Args[1] == "enable-user")
		if err != nil {
			fatal(err)
		}
		fmt.Printf("Updated %s\n", os.Args[2])
	default:
		usage()
	}
}
func dataPath() string {
	p := os.Getenv("PAIRDESK_DATA")
	if p == "" {
		return "./data/pairdesk.json"
	}
	return p
}
func password() (string, error) {
	if p := os.Getenv("PAIRDESK_ADMIN_PASSWORD"); p != "" {
		return p, nil
	}
	fmt.Fprint(os.Stderr, "Password (12+ chars): ")
	b, e := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Fprintln(os.Stderr)
	if e == nil {
		return string(b), nil
	}
	fmt.Fprintln(os.Stderr, "Enter password on stdin:")
	v, e := bufio.NewReader(os.Stdin).ReadString('\n')
	return strings.TrimSpace(v), e
}
func usage() {
	fmt.Fprintln(os.Stderr, "usage: pairdesk-admin create-user --name NAME --email EMAIL [--admin] | disable-user EMAIL | enable-user EMAIL")
	os.Exit(2)
}
func fatal(e error) { fmt.Fprintln(os.Stderr, e); os.Exit(1) }
