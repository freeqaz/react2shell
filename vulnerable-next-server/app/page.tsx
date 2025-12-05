import { echo, ping, submitForm, reflect } from "./actions";

export default function Home() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-zinc-50 font-sans dark:bg-black">
      <main className="flex min-h-screen w-full max-w-3xl flex-col items-center gap-8 py-16 px-8 bg-white dark:bg-black">
        <h1 className="text-2xl font-bold text-black dark:text-white">
          Vulnerable Next.js Server (v16.0.6)
        </h1>
        <p className="text-zinc-600 dark:text-zinc-400 text-center max-w-md">
          This server uses React 19.2.0 with vulnerable RSC deserialization.
          Server actions below demonstrate legitimate RSC traffic.
        </p>

        {/* Ping Form */}
        <section className="w-full max-w-md border border-zinc-200 dark:border-zinc-800 rounded-lg p-6">
          <h2 className="text-lg font-semibold mb-4 text-black dark:text-white">
            Ping Action
          </h2>
          <form
            action={async () => {
              "use server";
              const result = await ping();
              console.log("Ping result:", result);
            }}
          >
            <button
              type="submit"
              className="w-full bg-blue-600 text-white py-2 px-4 rounded hover:bg-blue-700 transition"
            >
              Ping Server
            </button>
          </form>
        </section>

        {/* Echo Form */}
        <section className="w-full max-w-md border border-zinc-200 dark:border-zinc-800 rounded-lg p-6">
          <h2 className="text-lg font-semibold mb-4 text-black dark:text-white">
            Echo Action
          </h2>
          <form
            action={async (formData: FormData) => {
              "use server";
              const message = formData.get("message") as string;
              const result = await echo(message);
              console.log("Echo result:", result);
            }}
            className="flex flex-col gap-4"
          >
            <input
              type="text"
              name="message"
              placeholder="Enter a message..."
              className="border border-zinc-300 dark:border-zinc-700 rounded px-4 py-2 bg-white dark:bg-zinc-900 text-black dark:text-white"
            />
            <button
              type="submit"
              className="bg-green-600 text-white py-2 px-4 rounded hover:bg-green-700 transition"
            >
              Send Echo
            </button>
          </form>
        </section>

        {/* Generic Form Submission */}
        <section className="w-full max-w-md border border-zinc-200 dark:border-zinc-800 rounded-lg p-6">
          <h2 className="text-lg font-semibold mb-4 text-black dark:text-white">
            Form Submit Action
          </h2>
          <form
            action={async (formData: FormData) => {
              "use server";
              const result = await submitForm(formData);
              console.log("Submit result:", result);
            }}
            className="flex flex-col gap-4"
          >
            <input
              type="text"
              name="name"
              placeholder="Name"
              className="border border-zinc-300 dark:border-zinc-700 rounded px-4 py-2 bg-white dark:bg-zinc-900 text-black dark:text-white"
            />
            <input
              type="text"
              name="value"
              placeholder="Value"
              className="border border-zinc-300 dark:border-zinc-700 rounded px-4 py-2 bg-white dark:bg-zinc-900 text-black dark:text-white"
            />
            <button
              type="submit"
              className="bg-purple-600 text-white py-2 px-4 rounded hover:bg-purple-700 transition"
            >
              Submit Form
            </button>
          </form>
        </section>

        {/* Reflect Action - direct string arg, returns it back */}
        <section className="w-full max-w-md border border-zinc-200 dark:border-zinc-800 rounded-lg p-6">
          <h2 className="text-lg font-semibold mb-4 text-black dark:text-white">
            Reflect Action
          </h2>
          <form
            action={async (formData: FormData) => {
              "use server";
              const data = formData.get("data") as string;
              const result = await reflect(data);
              console.log("Reflect result:", result);
            }}
            className="flex flex-col gap-4"
          >
            <input
              type="text"
              name="data"
              placeholder="Data to reflect..."
              className="border border-zinc-300 dark:border-zinc-700 rounded px-4 py-2 bg-white dark:bg-zinc-900 text-black dark:text-white"
            />
            <button
              type="submit"
              className="bg-orange-600 text-white py-2 px-4 rounded hover:bg-orange-700 transition"
            >
              Reflect
            </button>
          </form>
        </section>

        <p className="text-xs text-zinc-500 mt-8">
          React {process.env.npm_package_dependencies_react || "19.2.0"} |
          Next.js {process.env.npm_package_dependencies_next || "16.0.6"}
        </p>
      </main>
    </div>
  );
}
