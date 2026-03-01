// Ambient type declarations for @anon-aadhaar/core.
//
// This package ships raw .ts source files that fail type-checking under
// our tsconfig (strict mode + newer TS target).  This declaration file
// overrides the package's exports so tsc uses these clean types instead.

declare module '@anon-aadhaar/core' {
    // --- Core API --------------------------------------------------------
    export function init(args: InitArgs): Promise<void>;
    export function verify(pcd: any, useTestAadhaar?: boolean): Promise<boolean>;
    export function deserialize(serialized: string): Promise<any>;
    export function hash(...args: any[]): string;

    // --- Artifacts -------------------------------------------------------
    export const artifactUrls: {
        v2: { wasm: string; zkey: string; vk: string };
        v1: { wasm: string; zkey: string; vk: string };
        [key: string]: any;
    };

    export enum ArtifactsOrigin {
        server = 'server',
        local = 'local',
    }

    // --- Types -----------------------------------------------------------
    export interface InitArgs {
        wasmURL: string;
        zkeyURL: string;
        vkeyURL: string;
        artifactsOrigin?: ArtifactsOrigin;
        isWebEnv?: boolean;
        [key: string]: any;
    }

    export const defaultInitArgs: any;
}
