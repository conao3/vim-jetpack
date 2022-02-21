"=============== JETPACK.vim =================
"      The lightning-fast plugin manager
"     Copyrigh (c) 2022 TANGUCHI Masaya.
"          All Rights Reserved.
"=============================================

let g:jetpack#optimization = 1
let g:jetpack#njobs = 8

if has('nvim')
  let s:home = expand(stdpath('data') . '/site')
elseif has('win32') || has('win64')
  let s:home = expand('~/vimfiles')
else
  let s:home = expand('~/.vim')
endif

let s:optdir = { ->  s:path(s:home, '/pack/jetpack/opt') }
let s:srcdir = { ->  s:path(s:home, '/pack/jetpack/src') }

let s:pkgs = []
let s:ignores = [
\   '/doc/tags*',
\   '/.*',
\   '/.*/**/*',
\   '/t/**/*',
\   '/test/**/*',
\   '/VimFlavor*',
\   '/Flavorfile*',
\   '/README*',
\   '/Rakefile*',
\   '/Gemfile*',
\   '/Makefile*',
\   '/LICENSE*',
\   '/LICENCE*',
\   '/CONTRIBUTING*',
\   '/CHANGELOG*',
\   '/NEWS*',
\ ]

let s:progress_type = {
\   'skip': 'skip',
\   'install': 'install',
\   'update': 'update',
\ }

function s:path(...)
  return expand(join(a:000, '/'))
endfunction

function s:match(a, b)
  return a:a =~# '\V'.escape(a:b, '\')
endfunction

function s:substitute(a, b, c)
  return substitute(a:a, '\V' . escape(a:b, '\'), escape(a:c, '\'), '')
endfunction

function! s:files(path) abort
  return filter(glob(a:path . '/**/*', '', 1), '!isdirectory(v:val)')
endfunction

function! s:ignorable(filename) abort
  return filter(copy(s:ignores), 'a:filename =~? glob2regpat(v:val)') != []
endfunction

function! s:progressbar(n) abort
  return '[' . join(map(range(0, 100, 3), {_, v -> v < a:n ? '=' : ' '}), '') . ']'
endfunction

function! s:jobstatus(job) abort
  if has('nvim')
    return jobwait([a:job], 0)[0] == -1 ? 'run' : 'dead'
  endif
  return job_status(a:job)
endfunction

function! s:jobcount(jobs) abort
  return len(filter(copy(a:jobs), 's:jobstatus(v:val) ==# "run"'))
endfunction

function! s:jobwait(jobs, njobs) abort
  let running = s:jobcount(a:jobs)
  while running > a:njobs
    let running = s:jobcount(a:jobs)
  endwhile
endfunction

if has('nvim')
  function! s:jobstart(cmd, cb) abort
    let buf = []
    return jobstart(a:cmd, {
    \   'on_stdout': { _, data -> extend(buf, data) },
    \   'on_stderr': { _, data -> extend(buf, data) },
    \   'on_exit': { -> a:cb(join(buf, "\n")) }
    \ })
  endfunction
else
  " See https://github.com/lambdalisue/vital-Whisky/blob/90c715b446993bf5bfcf6f912c20ae514051cbb2/autoload/vital/__vital__/System/Job/Vim.vim#L46
  " See https://github.com/lambdalisue/vital-Whisky/blob/90c715b446993bf5bfcf6f912c20ae514051cbb2/LICENSE
  function! s:exit_cb(buf, cb, job, ...) abort
    let ch = job_getchannel(a:job)
    while ch_status(ch) ==# 'open' | sleep 1ms | endwhile
    while ch_status(ch) ==# 'buffered' | sleep 1ms | endwhile
    call a:cb(join(a:buf, "\n"))
  endfunction
  function! s:jobstart(cmd, cb) abort
    let buf = []
    return job_start(a:cmd, {
    \   'out_mode': 'raw',
    \   'out_cb': { _, data -> extend(buf, split(data, "\n")) },
    \   'err_mode': 'raw',
    \   'err_cb': { _, data -> extend(buf, split(data, "\n")) },
    \   'exit_cb': function('s:exit_cb', [buf, a:cb])
    \ })
  endfunction
endif

function! s:copy(from, to) abort
  call mkdir(fnamemodify(a:to, ':p:h'), 'p')
  if has('nvim')
    call v:lua.vim.loop.fs_link(a:from, a:to)
  elseif has('unix')
    call system(printf('ln -f "%s" "%s"', a:from, a:to))
  else
    call writefile(readfile(a:from, 'b'), a:to, 'b')
    call setfperm(a:to, getfperm(a:from))
  endif
endfunction

function! s:syntax() abort
  syntax clear
  syntax match jetpackProgress /[A-Z][a-z]*ing/
  syntax match jetpackComplete /[A-Z][a-z]*ed/
  syntax keyword jetpackSkipped Skipped
  highlight def link jetpackProgress DiffChange
  highlight def link jetpackComplete DiffAdd
  highlight def link jetpackSkipped DiffDelete
endfunction

function! s:setbufline(lnum, text, ...) abort
  call setbufline('JetpackStatus', a:lnum, a:text)
  redraw
endfunction

function! s:setupbuf() abort
  silent! execute 'bdelete! ' . bufnr('JetpackStatus')
  silent 40vnew +setlocal\ buftype=nofile\ nobuflisted\ noswapfile\ nonumber\ nowrap JetpackStatus
  call s:syntax()
  redraw
endfunction

function! jetpack#install(...) abort
  call s:setupbuf()
  let jobs = []
  for i in range(len(s:pkgs))
    let pkg = s:pkgs[i]
    call s:setbufline(1, printf('Install Plugins (%d / %d)', (len(jobs) - s:jobcount(jobs)), len(s:pkgs)))
    call s:setbufline(2, s:progressbar((0.0 + len(jobs) - s:jobcount(jobs)) / len(s:pkgs) * 100))
    call s:setbufline(i+3, printf('Installing %s ...', pkg.name))
    if (a:0 > 0 && index(a:000, pkg.name) < 0) || isdirectory(pkg.pathname)
      call s:setbufline(i+3, printf('Skipped %s', pkg.name))
      continue
    endif
    let cmd = ['git', 'clone']
    if !pkg.commit
      call extend(cmd, ['--depth', '1'])
    endif
    if type(pkg.branch) == v:t_string
      call extend(cmd, ['-b', pkg.branch])
    endif
    call extend(cmd, [pkg.url, pkg.pathname])
    let job = s:jobstart(cmd, function({ i, pkg, output -> [
    \   extend(pkg, {
    \     'progress': {
    \       'type': s:progress_type.install,
    \       'output': output
    \     }
    \   }),
    \   s:setbufline(i+3, printf('Installed %s', pkg.name))
    \ ] }, [i, pkg]))
    call add(jobs, job)
    call s:jobwait(jobs, g:jetpack#njobs)
  endfor
  call s:jobwait(jobs, 0)
endfunction

function! jetpack#update(...) abort
  call s:setupbuf()
  let jobs = []
  for i in range(len(s:pkgs))
    let pkg = s:pkgs[i]
    call s:setbufline(1, printf('Update Plugins (%d / %d)', (len(jobs) - s:jobcount(jobs)), len(s:pkgs)))
    call s:setbufline(2, s:progressbar((0.0 + len(jobs) - s:jobcount(jobs)) / len(s:pkgs) * 100))
    call s:setbufline(i+3, printf('Updating %s ...', pkg.name))
    if pkg.progress.type ==# s:progress_type.install || (a:0 > 0 && index(a:000, pkg.name) < 0) || (pkg.frozen || !isdirectory(pkg.pathname))
      call s:setbufline(i+3, printf('Skipped %s', pkg.name))
      continue
    endif
    let cmd = ['git', '-C', pkg.pathname, 'pull', '--rebase']
    let job = s:jobstart(cmd, function({ i, pkg, output -> [
    \   extend(pkg, {
    \     'progress': {
    \       'type': s:progress_type.update,
    \       'output': output
    \     }
    \   }),
    \   s:setbufline(i+3, printf('Updated %s', pkg.name))
    \ ] }, [i, pkg]))
    call add(jobs, job)
    call s:jobwait(jobs, g:jetpack#njobs)
  endfor
  call s:jobwait(jobs, 0)
endfunction

function! jetpack#clean() abort
  for pkg in s:pkgs
    if isdirectory(pkg.pathname) && type(pkg.commit) == v:t_string
      if system(printf('git -c "%s" cat-file -t %s', pkg.pathname, pkg.commit)) !~# 'commit'
        call delete(pkg.pathname)
      endif
    endif
    if isdirectory(pkg.pathname) && type(pkg.branch) == v:t_string
      let branch = system(printf('git -C "%s" rev-parse --abbrev-ref HEAD', pkg.pathname))
      if pkg.branch != branch
        call delete(pkg.pathname, 'rf')
      endif
    endif
  endfor
endfunction

function! jetpack#bundle() abort
  call s:setupbuf()
  let bundle = []
  let unbundle = s:pkgs
  if g:jetpack#optimization >= 1
    let bundle = filter(copy(s:pkgs), 's:match(v:val["pathname"], s:srcdir()) && !v:val["opt"] && empty(v:val["do"])')
    let unbundle = filter(copy(s:pkgs), 's:match(v:val["pathname"], s:srcdir()) && (v:val["opt"] || !empty(v:val["do"]))') 
  endif

  call delete(s:optdir(), 'rf')
  let destdir = s:path(s:optdir(), '_')
  " Merge plugins if possible.
  let merged_count = 0
  let merged_files = {}
  for i in range(len(bundle))
    let pkg = bundle[i]
    call s:setbufline(1, printf('Merging Plugins (%d / %d)', merged_count, len(s:pkgs)))
    call s:setbufline(2, s:progressbar(1.0 * merged_count / len(s:pkgs) * 100))
    let srcdir = s:path(pkg.pathname, pkg.rtp)
    let srcfiles = filter(s:files(srcdir), '!s:ignorable(s:substitute(v:val, srcdir, ""))')
    let destfiles = map(copy(srcfiles), 's:substitute(v:val, srcdir, destdir)')
    let dupfiles = filter(copy(destfiles), '!s:ignorable(s:substitute(v:val, destdir, "")) && has_key(merged_files, v:val)')
    if g:jetpack#optimization == 1 && dupfiles != []
      call add(unbundle, pkg)
      continue
    endif
    for i in range(0, len(srcfiles) - 1)
      call s:copy(srcfiles[i], destfiles[i])
      let merged_files[destfiles[i]] = v:true
    endfor
    call s:setbufline(merged_count+3, printf('Merged %s ...', pkg.name))
    let merged_count += 1
  endfor

  " Copy plugins.
  for i in range(len(unbundle))
    let pkg = unbundle[i]
    call s:setbufline(1, printf('Copy Plugins (%d / %d)', i+merged_count, len(s:pkgs)))
    call s:setbufline(2, s:progressbar(1.0 * (i+merged_count) / len(s:pkgs) * 100))
    let srcdir = s:path(pkg.pathname, pkg.rtp)
    let destdir = s:path(s:optdir(), pkg.name)
    for srcfile in s:files(srcdir)
      let destfile = s:substitute(srcfile, srcdir, destdir)
      call s:copy(srcfile, s:substitute(srcfile, srcdir, destdir))
    endfor
    call s:setbufline(i+merged_count+3, printf('Copied %s ...', pkg.name))
  endfor
endfunction

function! s:display() abort
  call s:setupbuf()

  let msg = {}
  let msg[s:progress_type.skip] = 'Skipped'
  let msg[s:progress_type.install] = 'Installed'
  let msg[s:progress_type.update] = 'Updated'

  let line_count = 1
  for pkg in s:pkgs
    call s:setbufline(line_count, printf('%s %s', msg[pkg.progress.type], pkg.name))
    let line_count += 1

    let output = pkg.progress.output
    let output = substitute(output, '\r\n\|\r', '\n', 'g')

    if pkg.progress.type ==# s:progress_type.update
      let from_to = matchstr(output, 'Updating\s*\zs[^\n]\+')
      if from_to !=# ''
        call s:setbufline(line_count, printf('  Changes %s/compare/%s', pkg.url, from_to))
        let line_count += 1
      endif
    endif

    for o in split(output, '\n')
      if o !=# ''
        call s:setbufline(line_count, printf('  %s', o))
        let line_count += 1
      endif
    endfor
    call s:setbufline(line_count, '')
    let line_count += 1
  endfor
endfunction

function! jetpack#postupdate() abort
  silent! packadd _
  for pkg in s:pkgs
    if empty(pkg.do)
      continue
    endif
    let pwd = getcwd()
    if !s:match(pkg.pathname, s:srcdir())
      call chdir(pkg.pathname)
    else
      call chdir(s:path(s:optdir(), pkg.name))
      execute 'silent! packadd ' . pkg.name
    endif
    if type(pkg.do) == v:t_func
      call pkg.do()
    endif
    if type(pkg.do) != v:t_string
      continue
    endif
    if pkg.do =~# '^:'
      execute pkg.do
    else
      call system(pkg.do)
    endif
    call chdir(pwd)
  endfor
  silent! helptags ALL
endfunction

function! jetpack#sync() abort
  call jetpack#clean()
  call jetpack#install()
  call jetpack#update()
  call jetpack#bundle()
  call s:display()
  call jetpack#postupdate()
endfunction
command! JetpackSync call jetpack#sync()

function! jetpack#add(plugin, ...) abort
  let opts = a:0 > 0 ? a:1 : {}
  let name = get(opts, 'as', fnamemodify(a:plugin, ':t'))
  let pathname = get(opts, 'dir', s:path(s:srcdir(),  name))
  let pkg  = {
  \  'url': (a:plugin !~# ':' ? 'https://github.com/' : '') . a:plugin,
  \  'branch': get(opts, 'branch', get(opts, 'tag')),
  \  'commit': get(opts, 'commit'),
  \  'do': get(opts, 'do'),
  \  'rtp': get(opts, 'rtp', '.'),
  \  'name': name,
  \  'frozen': get(opts, 'frozen'),
  \  'pathname': pathname,
  \  'opt': get(opts, 'opt'),
  \  'progress': {
  \    'type': s:progress_type.skip,
  \    'output': 'Skipped',
  \  },
  \ }
  for it in flatten([get(opts, 'for', [])])
    let pkg.opt = 1
    execute printf('autocmd Jetpack FileType %s ++nested silent! packadd %s', it, name)
  endfor
  for it in flatten([get(opts, 'on', [])])
    let pkg.opt = 1
    if it =~? '^<Plug>'
      execute printf("nnoremap %s :execute '".'silent! packadd %s \| call feedkeys("\%s")'."'<CR>", it, name, it)
      execute printf("vnoremap %s :<C-U>execute '".'silent! packadd %s \| call feedkeys("gv\%s")'."'<CR>", it, name, it)
    else
      execute printf('autocmd Jetpack CmdUndefined %s ++nested silent! packadd %s', substitute(it, '^:', '', ''), name)
    endif
  endfor
  if pkg.opt
    let event = substitute(substitute(name, '\W\+', '_', 'g'), '\(^\|_\)\(.\)', '\u\2', 'g')
    execute printf('autocmd Jetpack SourcePost %s/%s/* doautocmd User Jetpack%s', escape(resolve(s:optdir()), '\'), name, event)
  elseif isdirectory(s:path(s:optdir(), name))
    execute 'silent! packadd! ' . name
  endif
  call add(s:pkgs, pkg)
endfunction

function! jetpack#begin(...) abort
  syntax off
  filetype off
  let s:pkgs = []
  augroup Jetpack
    autocmd!
  augroup END
  if a:0 != 0
    let s:home = a:1
    execute 'set packpath^=' . s:home
  endif
  command! -nargs=+ Jetpack call jetpack#add(<args>)
endfunction

function! jetpack#end() abort
  delcommand Jetpack
  silent! packadd! _
  syntax enable
  filetype plugin indent on
endfunction

function! jetpack#tap(name) abort
  return filter(copy(s:pkgs), "v:val['name'] == a:name") != [] && isdirectory(s:path(s:srcdir(), a:name))
endfunction
