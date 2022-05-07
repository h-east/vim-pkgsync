
let s:CMDFORMAT_CLONE = 'git -c credential.helper= clone --no-tags --single-branch --depth 1 https://github.com/%s/%s.git'
let s:CMDFORMAT_PULL  = 'git -c credential.helper= pull'

let s:KIND_UPDATING = 0
let s:KIND_INSTALLING = 1

function! pkgsync#common#get_config_path() abort
	return expand('~/pkgsync.json')
endfunction

function! pkgsync#common#read_config() abort
	if filereadable(pkgsync#common#get_config_path())
		let j = json_decode(join(readfile(pkgsync#common#get_config_path()), ''))
		if !has_key(j, 'packpath') || !has_key(j, 'plugins')
			call pkgsync#error(printf('%s is broken! Please you should remove it and try initialization again!', string(pkgsync#common#get_config_path())))
		endif
		return {
			\   'packpath': j['packpath'],
			\   'plugins': {
			\     'start': get(j['plugins'], 'start', {}),
			\     'opt': get(j['plugins'], 'opt', {}),
			\   }
			\ }
	else
		call pkgsync#error('You are not initialized vim-pkgsync! Please initialize it!')
	endif
endfunction

function! pkgsync#common#write_config(j) abort
	call writefile([json_encode(a:j)], pkgsync#common#get_config_path())
endfunction

function! pkgsync#common#make_params(pack_dir, start_d, opt_d) abort
	let params = []
	for d in [a:start_d, a:opt_d]
		let start_or_opt = (d == a:start_d ? 'start' : 'opt')
		for user_name in keys(d)
			let pack_dir = expand(join([a:pack_dir, 'pack', user_name, start_or_opt], '/'))
			if !isdirectory(pack_dir)
				call mkdir(pack_dir, 'p')
			endif
			for plugin_name in d[user_name]
				let plugin_dir = pack_dir .. '/' .. plugin_name
				if isdirectory(plugin_dir)
					let params += [{
						\   'name': printf('%s/%s', user_name, plugin_name),
						\   'cmd': s:CMDFORMAT_PULL,
						\   'cwd': plugin_dir,
						\   'arg': has('nvim') ? { 'lines': [] } : tempname(),
						\   'job': v:null,
						\   'kind': s:KIND_UPDATING,
						\   'running': v:true,
						\   'start_or_opt': start_or_opt,
						\   'plugin_dir': plugin_dir,
						\ }]
				else
					let params += [{
						\   'name': printf('%s/%s', user_name, plugin_name),
						\   'cmd': printf(s:CMDFORMAT_CLONE, user_name, plugin_name),
						\   'cwd': pack_dir,
						\   'arg': has('nvim') ? { 'lines': [] } : tempname(),
						\   'job': v:null,
						\   'kind': s:KIND_INSTALLING,
						\   'running': v:true,
						\   'start_or_opt': start_or_opt,
						\   'plugin_dir': plugin_dir,
						\ }]
				endif
			endfor
		endfor
	endfor
	return params
endfunction

function! pkgsync#common#start_jobs(params) abort
	if has('nvim')
		for param in a:params
			let param['job'] = jobstart(param['cmd'], {
				\ 'cwd': param['cwd'],
				\ 'on_stdout': function('s:system_onevent', [param['arg']]),
				\ 'on_stderr': function('s:system_onevent', [param['arg']]),
				\ })
		endfor
	else
		for param in a:params
			let param['job'] = job_start(param['cmd'], {
				\ 'cwd': param['cwd'],
				\ 'out_io': 'file',
				\ 'out_name': param['arg'],
				\ 'err_io': 'out',
				\ })
		endfor
	endif
endfunction

function! pkgsync#common#wait_jobs(params) abort
	let n = 0
	while n < len(a:params)
		for param in a:params
			if !param['running']
				continue
			endif

			if has('nvim')
				if -1 == jobwait([param['job']], 0)[0]
					continue
				endif
			else
				if 'run' == job_status(param['job'])
					continue
				endif
			endif

			let n += 1
			let param['running'] = v:false
			let kind_msg = (param['kind'] == s:KIND_UPDATING) ? 'Updating' : 'Installing'
			call pkgsync#output(printf('%3d/%d. %s %s(%s)',
				\	n, len(a:params), kind_msg, param['name'], param['start_or_opt']))

			if has('nvim')
				for line in param['arg']['lines']
					if !empty(trim(line))
						call pkgsync#output('  ' .. line)
					endif
				endfor
			else
				if filereadable(param['arg'])
					for line in readfile(param['arg'])
						if !empty(trim(line))
							call pkgsync#output('  ' .. line)
						endif
					endfor
					call delete(param['arg'])
				endif
			endif
		endfor
	endwhile
endfunction

function! pkgsync#common#helptags(params) abort
	for param in a:params
		if isdirectory(param['plugin_dir'] .. '/doc')
			execute printf('helptags %s', fnameescape(param['plugin_dir'] .. '/doc'))
		endif
	endfor
endfunction

function! pkgsync#common#delete_carefull(pack_dir, path) abort
	if (-1 != index(split(a:path, '[\/]'), 'pack')) && (a:path[:(len(a:pack_dir) - 1)] == a:pack_dir)
		call pkgsync#output(printf('Deleting the directory: "%s"', a:path))
		call delete(a:path, 'rf')
	endif
endfunction



function s:system_onevent(d, job, data, event) abort
	let a:d['lines'] += a:data
	sleep 10m
endfunction
