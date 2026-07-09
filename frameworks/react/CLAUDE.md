## Component Usage

When editing UI components, always check which custom components exist in the project (e.g., `<Button>`)
and what props they accept before using them. Never use plain HTML elements when a project component
exists, and never pass props (like `className`) that the component doesn't support.

When modifying existing UI components, reuse existing sub-components (arrows, navigation, badges) rather
than creating new ones. Check what already exists in the component before adding duplicates.

## CSS Conventions

Use `rem` units for all sizing/spacing, never `px`. Never use `margin-top`. Always nest CSS selectors
inside their parent blocks — do not place them outside.

All spacing and sizing values must align to a 4px grid. Using 1rem = 16px as the base, valid increments
are multiples of 0.25rem (0.25, 0.5, 0.75, 1rem, etc.). Do not use arbitrary values like 0.3rem or 0.6rem.

Use flexbox for layout by default. Do not use CSS grid without explicit approval from the user.

Use CSS variables from the project's variables file instead of raw values: colors (never hardcode hex/rgb),
semantic tokens over raw color variables, typography, shadows, and z-index (never raw numbers).
