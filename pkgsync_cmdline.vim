
let s:rootdir = expand('<sfile>:h')

function s:main() abort
	try
		let g:pkgsync_stdout = 1
		execute printf('source %s/autoload/pkgsync.vim', s:rootdir)
		call pkgsync#parse_cmdline(v:argv[3:])
		qall!
	catch
		put=v:exception
		print
		cquit!
	endtry
endfunction

call s:main()

