# draftsman.nvim

**Draftsman.nvim** is a Neovim plugin designed to draw ASCII and Unicode diagrams, flowcharts, and boxes effortlessly in Neovim, complete with a helpful sidebar UI to keep track of your tools and settings.

This plugin is inspired by [venn.nvim](https://github.com/jbyuki/venn.nvim) and [asciiflow](https://github.com/lewish/asciiflow).

```

     ┌────────────────┐
     │ Draw something │
     │ easily with    │
     │ draftsman.nvim │
     └─┬──────────────┘
       │
       ├──────────────────────────────────────────────── Copy and paste
       │                                                 using <v> and <p>
       │  ┌────────────────────────────┐  ┌─┐            ┌───┐ ┌───┐ ┌───┐
       ├──┤ Press <s> to start stroke  ├──┘ │ ┌────      │   │ │   │ │   │
       │  └────────────────────────────┘    └─┘          └───┘ └───┘ └───┘
       │  ┌────────────────────────────┐  ┌─┐   ↑        ┌───┐ ┌───┐ ┌───┐
       ├──┤ Press <a> to draw arrow    ├──┘ │ ┌─┼─→      │   │ │   │ │   │
       │  └────────────────────────────┘    └─┘ ↓        └───┘ └───┘ └───┘
       │                                                 ┌───┐ ┌───┐ ┌───┐
       │  Press <r> to draw rectangle                    │   │ │   │ │   │
       │  ┌───────────┐                                  └───┘ └───┘ └───┘
       │  │           │ Press <m> to move stroke
       ├──┤           ├─────────────────────────┐
       │  │           │                         │
       │  └───────────┴─────────────────────────┘
       │
       └──Draw with different styles
           ┌────┐  ╔════╗  +----+
           │    │  ║    ║  |    |
           └────┘  ╚════╝  +----+
           1       2       3


```

## Features & Usage

### Interactive Sidebar

Once you enter Draftsman mode (the default command is `DraftmanStart`), a sidebar will appear. The sidebar will display available operations and the current status.

Use `hjkl` to move as usual. Use `HJKL` (Shift + key) to move faster.
You can move any where on screen.

### Draw Stroke (`<s>`) and Arrow (`<a>`)

Draw continuous lines. The plugin handles corners and intersections automatically.

1. Press `s`/`a` to start.
2. Move cursor with `hjkl` and the line follow cursor's trait.
3. Press `s`/`a` again to stop.

<img width="428" height="350" alt="stroke" src="https://github.com/user-attachments/assets/704388f9-6cd8-4cbc-a8d5-3266847ccc32" />
<img width="456" height="350" alt="arrow" src="https://github.com/user-attachments/assets/fa0b900d-aab8-463f-a408-45729f251175" />


### Draw rectangle (`<r>`)

Draw rectangles instantly.

1. Press `r` to start a rectangle. A mark will appear.
2. Move your cursor to define the size.
3. Press `r` again to commit the shape to the canvas.

<img width="414" height="380" alt="rectangle" src="https://github.com/user-attachments/assets/dfccebd2-525a-4bd1-a141-6672d51fd279" />

### Text Insertion (`<i>`)

Press `i` to insert text. This allows you to type labels over lines without destroying the surrounding structure.

- `<CR>`: Moves down a line (preserving column start).
- `<Esc>`: Returns to drawing mode.

<img width="470" height="350" alt="text" src="https://github.com/user-attachments/assets/660d1a38-467a-4468-8610-c7f8c08177f6" />

### Move Stroke (`<m>`)

Grab a line segment and move it.

1. Press `m` on a line.
2. Move your cursor, and the edge moves with you.
3. Press `m` again to stop dragging the edge.

<img width="470" height="350" alt="move" src="https://github.com/user-attachments/assets/ecf0671a-415d-4ce8-bcd6-bbf804a8a93c" />

### Eraser (`<x>` and `<BS>`)

- `x`: Clears the character under the cursor.
- `<BS>`: Just Backspace (clears character to the left).

<img width="414" height="350" alt="eraser" src="https://github.com/user-attachments/assets/73f6bd96-798c-409e-8dc1-9d150b8652fc" />

### Clipboard & Selection

Draftsman has its own internal clipboard for moving parts of diagrams around.

- **Select (`v`)**: Enter visual selection mode. It is use for select rectangular area like press `<C-v>` in normal mode in vim.
  1.  Press `v` to start. a Mark will appear.
  2.  Move the cursor to choose a rectangular area.
  3.  Yank or delete the chosen area.
- **Yank (`y`)**: Copy the selected area.
- **Delete (`d`)**: Cut/Clear the selected area.
- **Paste (`p`)**: Paste the clipboard content at the current cursor position.

<img width="582" height="410" alt="clipboard" src="https://github.com/user-attachments/assets/dab1b5a6-9f94-4e05-bc2c-e6be27d6879b" />

### Different Styles

Switch line style by pressing `1`. `2`, or `3`. Current style will be shown in sidebar. Styles can be customized by configuration. The default styles are

- Style 1: single line.
- Style 2: double line.
- Style 3: ASCII.

<img width="568" height="350" alt="styles" src="https://github.com/user-attachments/assets/2ba69054-f583-4b36-a2b7-673378327050" />

### Other Keys

Some keys are remapped to behave similarly to their original Vim functions while being better suited for drawing.

| Key     | Action                                   |
| ------- | ---------------------------------------- |
| `?`     | Toggle Help in Sidebar                   |
| `o/O`   | Insert a blank line while keeping cursor |
| `%`     | Jump to a connected segment end           |
| `u`     | Undo                                     |
| `<C-r>` | Redo                                     |
| `<Esc>` | Exit                                     |

## Installation

Install using your favorite package manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "chenyu76/draftsman.nvim",
    config = function()
        require("draftsman").setup({})
    end
}

```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use({
	"chenyu76/draftsman.nvim",
	config = function()
		require("draftsman").setup()
	end,
})
```

## Configuration

Draftsman comes with sensible defaults. You can override the line styles or integration settings by passing a table to the setup function.

**Default Configuration:**

```lua
require("draftsman").setup({
	styles = {
		[1] = { -- Single Line (Default)
			[[┌┬┐↑]],
			[[├┼┤│]],
			[[└┴┘↓]],
			[[←─→ ]],
		},
		[2] = { -- Double Line
			[[╔╦╗▲]],
			[[╠╬╣║]],
			[[╚╩╝▼]],
			[[◄═► ]],
		},
		[3] = { -- ASCII / Classic
			[[+++^]],
			[[+++|]],
			[[+++v]],
			[[<-> ]],
		},
	},
	integrations = {
		-- Draftsman disables mini.nvim in diagram mode
		-- to prevent conflict with drawing mappings.
		minisurround = true,
		miniai = true,
		miniindentscope = true,
		minipairs = true,
	},
	cmd = {
		"DraftsmanStart",
		"DraftsmanStop",
		"DraftsmanToggle",
	},
	key = {
		stroke = "s",
		arrow = "a",
		rectangle = "r",
		move = "m",
		insert_text = "i",
	},
})
```

## Known Problem

- Some wide characters (`\t`, CJK, etc.) have strange behaviour.
