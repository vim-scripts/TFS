" vim70
"
" Vim plugin to assist in working with files under TFS version control.
"
" Maintainer:   Ben Staniford <ben at staniford dot net> License: Copyright
" (c) 2011 Ben Staniford
"
" Version: 1.1.2
"
" Permission is hereby granted, free of charge, to any person obtaining a copy
" of this software and associated documentation files (the "Software"), to
" deal in the Software without restriction, including without limitation the
" rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
" sell copies of the Software, and to permit persons to whom the Software is
" furnished to do so, subject to the following conditions:
"
" The above copyright notice and this permission notice shall be included in
" all copies or substantial portions of the Software.
"
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
" IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
" FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
" AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
" LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
" FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
" IN THE SOFTWARE.
"
" Section: Documentation {{{1
"
" Provides functions to invoke various TFS source control commands on the
" current file.  The output of the commands is captured in a new scratch window.
"

if has ('win32')

"
" TFS will be 32 bit even if vim is 64 bit
"
if ($PROCESSOR_ARCHITECTURE == "AMD64")
    " Vim appears not to be able to cope with env vars like $PROGRAMFILES(X86)
    " So on 64bit Vim we have to guess from the 64 bit variable.
    let s:pfiles = $PROGRAMFILES.' (x86)'
else
    let s:pfiles = $PROGRAMFILES
endif

"
" Work out which versions of tf.exe and tfpt.exe are available
"
if (filereadable(s:pfiles.'\Microsoft Visual Studio 10.0\Common7\IDE\TF.exe'))
    let s:tfs_tf='"'.s:pfiles.'\Microsoft Visual Studio 10.0\Common7\IDE\TF.exe"'
    let s:tfs_recurse_command='/recursive'
elseif(filereadable(s:pfiles.'\Microsoft Visual Studio 9.0\Common7\IDE\TF.exe'))
    let s:tfs_tf='"'.s:pfiles.'\Microsoft Visual Studio 9.0\Common7\IDE\TF.exe"'
    let s:tfs_recurse_command='/recursive'
elseif(filereadable(s:pfiles.'\Microsoft Visual Studio 8\Common7\IDE\TF.exe'))
    let s:tfs_tf='"'.s:pfiles.'\Microsoft Visual Studio 8\Common7\IDE\TF.exe"'
    let s:tfs_recurse_command='/followbranches'
endif
if (filereadable(s:pfiles.'\Microsoft Team Foundation Server 2010 Power Tools\TFPT.exe'))
    let s:tfs_tfpt='"'.s:pfiles.'\Microsoft Team Foundation Server 2010 Power Tools\TFPT.exe"'
elseif (filereadable(s:pfiles.'\Microsoft Team Foundation Server 2008 Power Tools\TFPT.exe'))
    let s:tfs_tfpt='"'.s:pfiles.'\Microsoft Team Foundation Server 2008 Power Tools\TFPT.exe"'
elseif (filereadable(s:pfiles.'\Microsoft Team Foundation Server 2005 Power Tools\TFPT.exe'))
    let s:tfs_tfpt='"'.s:pfiles.'\Microsoft Team Foundation Server 2005 Power Tools\TFPT.exe"'
endif

"
" Window modes/defaults for command output
"
let s:window_mode_viewer     = 1
let s:window_mode_popup      = 2
let s:popup_size             = 5
let s:bigpopup_size          = 15

"
" Debug commands
"
let g:tfs_debug_mode = 0

" -----------------------------------------------------------------------------------------

"
" Display the results of a TFS command in a window
"
" parameters
"
" cmdline  - The TFS command to run in the new window
"
" label    - A label to identify temp file (can be empty for popup windows)
"
" filetype - The extension of the code file the user was editing (can be empty 
"            for popup windows)
"
" mode     - Can be s:window_mode_viewer for viewing code etc, or s:window_mode_popup
"            which simply shows the TFS output of a command in a small window.
"
" size     - The max size in lines of a popup window (doesn't relate to viewer
"            windows)
"
function! TfWindow(cmdline, label, filetype, mode, size)

    set buftype=nofile
    set switchbuf=useopen

    if (a:mode == s:window_mode_popup)
        let tmpfile = "tfcmd"
        let winpos = "botright"
    else
        let tmpfile = tempname().a:label.".".a:filetype
        let winpos = "topleft"
    endif

    " Split the window
    let buf = bufnr(tmpfile, 1)
    exe "noautocmd ".winpos." sb ".buf

    " Clear previous contents if this is a popup
    if (a:mode == s:window_mode_popup)
        norm 1GdG
    endif

    " Set up the output buffer
    set buftype=nofile
    setlocal noswapfile
    setlocal modifiable
    setlocal nopaste

	let escaped_cmdline='cmd /c "'.a:cmdline.'"'

    if (a:mode == s:window_mode_popup && g:tfs_debug_mode)
		put =escaped_cmdline
		norm o
	endif

    " Execute the TFS command in such as was as to allow ^"^" quoting of
	" parameters
    silent! exe 'noautocmd r!'.escaped_cmdline

    " Make sure syntax highlighting works if we're viewing code
    filetype detect
    setlocal nomodified

    " Make window as big as output upto maximum of size param
    if (a:mode == s:window_mode_popup)
        norm 1Gdd
		let lastline = line('$')
		if (lastline > a:size)
			exe "resize ".a:size
		else
			exe 'resize '.(lastline + 1)
		endif
    endif

	" Return to users code window
	wincmd p

	" Refresh the previous window to reflect any TFS changes
    if (a:mode != s:window_mode_viewer)
		edit!
	endif

	" Remove options we added to users previous window
    set switchbuf=
    set buftype=

	" If we're in viewer mode, leave the cursor in the new viewer window
    if (a:mode == s:window_mode_viewer)
		wincmd p
	endif

endfunction

" -----------------------------------------------------------------------------------------

"
" View a particular version of a file, or prompt..
"
function! TfViewVer(...)
    
    if (a:0 == 0)
        let ver = input("Changeset: ")
    else
        let ver = a:1
    endif

    let file_path=expand('%:p')

    if (ver < 0)
        let cmd=s:tfs_tf.' view /console ^"'.file_path.'^"'
    else
        let cmd=s:tfs_tf.' view /console ^"'.file_path.'^" /version:'.ver
    endif

    call TfWindow(cmd, ver, expand('%:e'), s:window_mode_viewer, 0)

endfunction

" -----------------------------------------------------------------------------------------

"
" Get a specific version of this file
"
function! TfGetVersion(...)
        
    let fver = ""
    if (a:0 > 0)
        let fver = a:1
    else
        let fver = input("Changeset: ")
    endif

    call TfPopup('get /version:'.fver)

endfunction

" -----------------------------------------------------------------------------------------

"
" Diff current file with particular version, or prompt...
"
function! TfDiffVer(...)

    let curfile = expand('%:p')

    if (a:0 > 0)
        call TfViewVer(a:1)
    else
        call TfViewVer()
    endif

    wincmd o
    exe 'vert diffsplit '.curfile

endfunction

" -----------------------------------------------------------------------------------------

"
" Perform the actual check-in (called after comments file saved)
"
function! TfCheckin(checkinfile, commentfile)

    let command = s:tfs_tf.' checkin ^"'.a:checkinfile.'^" /comment:@'.a:commentfile
    exe 'bd '.a:commentfile
    wincmd t
    exe 'e '.a:checkinfile
    call TfWindow(command, "", "human", s:window_mode_popup, s:popup_size)
    filetype detect

endfunction

" -----------------------------------------------------------------------------------------

"
" Allow user to type in check-in comments
"
function! TfGetCheckinComments()

    let s:tfs_commentfile = tempname()."-checkin.txt"
    let s:tfs_tocheckin = expand('%:p')
    let buf = bufnr(s:tfs_commentfile, 1)

    " Show window for user to type check-in comments
    exe "noautocmd botright sb ".buf
    resize 10
    exe 'botright edit '.s:tfs_commentfile
    norm i// Type your check-in comment below and :w to check-in
    norm o
    norm o
    norm ^d$

    " Clear any comments before the user saves
    autocmd BufWrite <buffer> :exe '%s/^\/\/.*$\n//g'

    " Perform check-in once comment file is closed
    autocmd BufWritePost <buffer> :call TfCheckin(s:tfs_tocheckin, s:tfs_commentfile)

endfunction

" -----------------------------------------------------------------------------------------

"
" Run a raw TF/TFTP command
"
function! TfCmd(exe, cmds)
    let command = a:exe.' '.a:cmds
    call TfWindow(command, "", "human", s:window_mode_popup, s:bigpopup_size)
endfunction

" -----------------------------------------------------------------------------------------

" Launch TFS UI command asynchronously
function! TfUiCmd(exe, cmds)

	" Set CWD to file path, launch TF/TFPT, restore CWD
	let owd = getcwd()
	let filepath = expand('%:p:h')
	silent! exe 'lcd '.filepath
	echo filepath
    let command = a:exe.' '.a:cmds

	" To debug, switch to cmd /k
	silent! exe '! start /min cmd /c '.command
	silent! exe 'lcd '.owd

	" Give some feedback so user doesn't think it's failed
	redraw!
    if (g:tfs_debug_mode)
		echom command
	else
		echom "Launching TFS UI..."
	endif
	
endfunction

" -----------------------------------------------------------------------------------------

function! TfPopup(cmd)
    let command = s:tfs_tf.' '.a:cmd.' ^"'.expand('%:p').'^"'
    call TfWindow(command, "", "human", s:window_mode_popup, s:popup_size)
endfunction

" -----------------------------------------------------------------------------------------

function! TfBigPopup(cmd)
    let command = s:tfs_tf.' '.a:cmd.' ^"'.expand('%:p').'^"'
    call TfWindow(command, "", "human", s:window_mode_popup, s:bigpopup_size)
endfunction

" -----------------------------------------------------------------------------------------

"
" TFS Vim Commands
"
command! TfCheckout                   :call TfPopup("checkout")
command! TfCheckin                    :call TfGetCheckinComments()
command! TfRevert                     :call TfPopup("undo")
command! TfStatus                     :call TfBigPopup("status")
command! TfAdd                        :call TfPopup("add")
command! TfHelp                       :call TfCmd(s:tfs_tf, "help")
command! TfGetLatest                  :call TfPopup("get")
command! TfShelve                     :call TfUiCmd(s:tfs_tf, "shelve")
command! TfUnshelve                   :call TfUiCmd(s:tfs_tf, "unshelve")
command! TfCheckinAll                 :call TfUiCmd(s:tfs_tf, "checkin")
command! TfReview                     :call TfUiCmd(s:tfs_tfpt, "review")
command! TfPtHelp                     :call TfCmd(s:tfs_tfpt, "help")
command! -complete=file -nargs=1 Tf   :call TfCmd(s:tfs_tf, <args>)
command! -complete=file -nargs=1 TfPt :call TfCmd(s:tfs_tfpt, <args>)
command! -nargs=? TfGetVersion        :call TfGetVersion(<args>)
command! TfHistory                    :call TfWindow(s:tfs_tf.' history '.s:tfs_recurse_command.' ^"#^"', "", "tfcmd", s:window_mode_popup, s:bigpopup_size)
command! TfHistoryDetailed            :call TfWindow(s:tfs_tf.' history /format:detailed '.s:tfs_recurse_command.' ^"#^"', "", "tfcmd", s:window_mode_popup, s:bigpopup_size)
command! TfAnnotate                   :call TfUiCmd(s:tfs_tfpt, "annotate ".expand('%:p'))
command! TfDiffLatest                 :call TfDiffVer("T")
command! -nargs=? TfDiffVer           :call TfDiffVer(<args>)
command! -nargs=? TfViewVer           :call TfViewVer(<args>)

" -----------------------------------------------------------------------------------------

"
" TFS Menu
"
if has('gui') && ( ! exists('g:tfs_menu') || g:tfs_menu != 0 )
    amenu <silent> &TFS.&Add                  :TfAdd<cr>
    amenu <silent> &TFS.Check-&out            :TfCheckout<cr>
    amenu <silent> &TFS.Check-&in             :TfCheckin<cr>
    amenu <silent> &TFS.&Get\ Latest          :TfGetLatest<cr>
    amenu <silent> &TFS.Get\ &Version         :TfGetVersion<cr>
    amenu <silent> &TFS.&Revert               :TfRevert<cr>
    amenu <silent> &TFS.&History              :TfHistory<cr>
    amenu <silent> &TFS.A&nnotations          :TfAnnotate<cr>
    amenu <silent> &TFS.D&etailed\ History    :TfHistoryDetailed<cr>
    amenu <silent> &TFS.Diff\ with\ &Latest   :TfDiffLatest<cr>
    amenu <silent> &TFS.View\ Ve&rsion        :TfViewVer<cr>
    amenu <silent> &TFS.&Diff\ with\ Version  :TfDiffVer<cr>
    amenu <silent> &TFS.-Sep- :
    amenu <silent> &TFS.&Status               :TfStatus<cr>
    amenu <silent> &TFS.Review                :TfReview<cr>
    amenu <silent> &TFS.Check-in\ All         :TfCheckinAll<cr>
    amenu <silent> &TFS.Create\ Shelveset     :TfShelve<cr>
    amenu <silent> &TFS.&Unshelve\ Shelveset  :TfUnshelve<cr>
endif

"
" TFS key mappings
"
noremap \ta :TfAdd<cr>
noremap \to :TfCheckout<cr>
noremap \ti :TfCheckin<cr>
noremap \tl :TfGetLatest<cr>
noremap \tr :TfRevert<cr>
noremap \th :TfHistory<cr>
noremap \tv :TfViewVer<cr>
noremap \td :TfDiffVer<cr>
noremap \tt :TfDiffLatest<cr>
noremap \ts :TfStatus<cr>
noremap \tc :TfCheckinAll<cr>
noremap \te :TfShelve<cr>
noremap \tu :TfUnshelve<cr>

endif
