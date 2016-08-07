function Get-MarkdownLink
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [string[]]$Path = '.',

        [switch]$ThrowOnBroken,

        [switch]$BrokenOnly
    )

    begin
    {
        $builder = [Markdig.MarkdownPipelineBuilder]::new()
        # use UsePreciseSourceLocation for better error reporting
        $pipeline = [Markdig.MarkdownExtensions]::UsePreciseSourceLocation($builder).Build()
        $hasBroken = @($false)
    }

    process
    {
        function handleOneFile
        {
            param(
                [string]$File
            )

            Write-Verbose "Process $File"

            $root = Split-Path $File
            $s = Get-Content -Raw $File
            if (-not $s)
            {
                Write-Verbose "$File is empty"
                return
            }

            $ast = [Markdig.Markdown]::Parse($s, $pipeline)
            $rawLinks = $ast.Inline | ? {$_ -is [Markdig.Syntax.Inlines.LinkInline]}
            $links = $rawLinks | % {
                $url = $_.Url
                $isAbsolute = Test-LinkAsUri $url

                $isBroken = if ($isAbsolute) {
                    # we probably can add a switch to check absolute URIs accessibility,
                    # but it's hard due to the random network problems and liquid nature
                    # of the internet.
                    $false 
                }
                else {
                    -not (Test-LinkAsRelative $url $root)
                }

                # yeild
                New-Object -TypeName PSObject -Property @{
                    IsBroken = $isBroken
                    IsAbsolute = $isAbsolute
                    Text = if ($_.Content) { $_.Content.ToString() } else { '' }
                    Path = $File
                    Url = $_.Url
                    Line = $_.Line + 1
                    Column = $_.Column + 1
                }
            }

            $brokenLinks = $links | ? {$_.IsBroken}

            Write-Verbose "Found $($links.Count) links, $($brokenLinks.Count) broken links in $File"

            if ($brokenLinks)
            {
                $hasBroken[0] = $true
            }

            # format and return
            if ($BrokenOnly)
            {
                $links = $brokenLinks
            }

            $result = $links | Select-Object -Property Path, Text, Url, IsBroken, IsAbsolute, Line, Column
            $result
        }

        $Path | % {
            if (Test-Path $_ -PathType Container)
            {
                Get-ChildItem -Recurse -Filter '*.md' $_ | % {
                    handleOneFile $_.FullName
                }
            }
            elseif (Test-Path $_ -PathType Leaf)
            {
                handleOneFile $_
            }
            else 
            {
                throw "$_ is not a valid path"    
            }
        }
    }

    end 
    {
        if ($Throw -and $hasBroken[0])
        {
            throw "There are broken markdown links and Throw switch is specified"
        } 
    }
}

function Get-ChildItemViaLink
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [string[]]$Path = '.'
    )

    process
    {
        function iterate
        {
            param(
                [string[]]$Path
            )

            $links = Get-MarkdownLink -Path $Path | ? {
                (-not $_.IsAbsolute) -and (-not $_.IsBroken) -and ($_.Path) -and ($_.Url)
            }
            Write-Verbose "Found $($links.Count) links to process in $Path"
            $links | % {
                # ignore paragraph specification
                $url = $_.Url.Split('#')[0]
                $dest = (Resolve-Path (Join-Path (Split-Path $_.Path) $url)).Path
                if (Test-Path -PathType Leaf $dest)
                {
                    if (-not ($queue -contains $dest))
                    {
                        $queue.Add($dest)
                    }
                }
            }
        }

        $queue = New-Object 'System.Collections.Generic.List[string]'
        $index = 0

        iterate $Path
        while ($index -lt $queue.Count)
        {
            iterate $queue[$index++]
        }

        # return
        $queue | Get-ChildItem
    }
}

function Test-LinkAsUri
{
    param(
        [string]$link
    )

    try 
    {
        $uri = [uri]::new($link) 
        return $uri.IsAbsoluteUri
    }
    catch 
    {
        return $false    
    }
}

function Test-LinkAsRelative
{
    param(
        [string]$link,
        [string]$root
    )

    # ignore paragraph specification
    $link = $link.Split('#')[0]
    
    $relativePath = Join-Path $root $link
    return (Test-Path $relativePath)
}
